# Learning from other languages: XQuery and jq

Status: comparison study — extracts problems, decides nothing. Demands
are handed to the owning design docs; the design itself stays in the
design conversations.

This is the dataflow entry in the comparison series (`effekt-`, `raku-`,
`flix-comparison.md`). The earlier studies read foreign cores
re-deriving our capabilities. XQuery and jq are different: they *share*
our core — a pure pipeline over flows of values, iteration implicit, no
mutable state — as two independent, shipped implementations at two
scales. XQuery is a committee-designed query language whose FLWOR
machinery grew grouping and windowing clauses over a decade of revisions;
jq is a single-author streaming tool whose entire language fits in one
manual. Because they share the core, their walls, workarounds, and
bolted-on constructs read as field reports from our own future.

(Reactive programming is deliberately not this round: most of it lives in
libraries inside non-reactive languages, and reading it well needs a
library-corpus method — deferred to a later round.)

Corpus. XQuery: the XQuery 3.1 specification's FLWOR sections in full
(tuple streams; for/let with `allowing empty`; where; **the window
clause**, tumbling and sliding, with all spec examples; count; group by;
order by), the spec's appendix on recursive transformations, the XML
Query 1.0 Use Cases (XMP, TREE, SEQ, PARTS queries), the XQuery 3.0 Use
Cases windowing suite (data windowing and the event/CEP queries), and the
Update Facility spec (pending update lists, transform expressions). jq:
the jq 1.8 manual in full, the community wiki's Cookbook, FAQ, and
pitfalls pages (~25 complete programs), and `src/builtin.jq` for the
reference definitions of `limit`, `first`, `while`, `INDEX`.

## Reading rules for this corpus

Three standing cautions, plus two specific to XQuery/jq:

1. **What's out there is already out there.** The output is problems, not
   mechanisms. Duplicating jq would produce jq.
2. **Different core; bolting on clashes — *inverted*.** These are the
   first corpora that *share* our core, so the standing risk (grafting a
   foreign mechanism) flips: the risk here is mistaking familiarity for
   validation. Mitigation: read hardest where they strain — the
   workaround idioms, the constructs added in later revisions, and jq's
   community pitfalls page. A revision or a pitfall is a field report that
   the original core hit a wall.
3. **Maturity polish.** The W3C use cases were written to motivate
   features; the jq manual is the author's showcase. The jq Cookbook and
   FAQ are community answers to real problems — the most field-like
   material in this genre so far — but selection-biased toward the tricky.
   Frequencies mean nothing.
4. **Domain-bound corpora.** Both languages live on document
   transformation (XML, JSON). Restructuring, grouping, and deep-tree work
   are overweighted; long-running state, concurrency, and effects are
   underweighted — their near-absence is domain fact, not evidence of
   unimportance.
5. **Two languages, one round.** Findings are attributed per language;
   where both exhibit a shape independently, that is noted, since
   independent convergence is the strongest signal this genre produces.

## What the two languages do

**XQuery.** Everything routes through the FLWOR expression, whose
semantics the spec defines on a **tuple stream**: "a tuple is a set of
zero or more named variables, each bound to a value"; each clause takes
the tuple stream from the previous clause and produces a new one. `for`
multiplies tuples (dependent clauses nest; multiple clauses form
products, with `allowing empty` as the outer-join variant), `let` widens
them, `where` filters them, `order by` reorders them, `count` numbers
them, `group by` partitions them, the window clause segments them.
Sequences are flat by fiat — `(1, (2,3))` *is* `(1,2,3)` — so all nesting
lives in element construction. Path expressions (`//`, axes, predicates)
return distinct nodes in document order. The language is pure; mutation
is a separate facility (the Update Facility) with collect-then-apply
semantics.

**jq.** "A jq program is a 'filter': it takes an input, and produces an
output" — and an output is a *stream* of zero or more values. `|`
composes; `.[]` opens an array into its elements; `,` concatenates
streams; any expression may be multi-valued, and combining multi-valued
expressions takes Cartesian products ("jq is geared to produce Cartesian
products at the drop of a hat" — the pitfalls page). `empty` produces no
values and backtracks; `//` falls back when the left side yields nothing
truthy; `first`/`limit` commit via lexical `label`/`break`. State is
`reduce`/`foreach`; recursion is `def`. The other half of the language is
**paths**: any filter, run in a path context, denotes the list of
locations it selects, and every assignment form (`=`, `|=`, `+=`, `del`)
is defined as "whichever paths it selects from the input will be where
the assignment is performed" — functional deep update over immutable
values.

## The material, against the record

### 1. The tuple stream — a shipped language arrives at barriers-not-bottlenecks

**Their approach.** FLWOR's semantic object is not a value pipeline but a
stream of *named multi-wire bindings*. When a `where`, `order by`, or
`count` clause processes the stream, every variable passes through as
itself: "the output tuple stream of the order by clause contains the same
tuples as its input tuple stream, but the tuples may be in a different
order." A join is written by letting a dependent `for` range over a
filtered second source while `$s` stays in scope (`for $s in $sales, $p
in $products[itemno = $s/itemno]`), and both wires flow onward. No packing
anywhere.

jq is the control experiment. Its pipeline carries exactly **one** value
— `.` — so keeping two things in flight means either binding (`. as $row
| ...`) or packing an object. The Cookbook is dense with both: the
column-headers recipe packs and re-reads (`.rows | map(. as $row |
$headers | with_entries(...))`); the per-machine aggregation threads
`$line.machine as $machine | $line.domain as $domain | ...` through every
step; `INDEX`'s own definition packs `[., $idx[idx_expr]]` pairs just to
move two values one step. The manual even has to warn that `$var.foo = 1`
is meaningless — the one implicit wire is also the only assignable one.

**Our approach.** This is the no-bottlenecks principle (`core-model.md`,
barriers with corresponding inputs and outputs) observed in the wild from
both sides at once: the language with named multi-wire tuples composes
clause after clause without packing; the language with a single anonymous
wire pays a binding or a tuple at every step where two values coexist.
FLWOR's tuple stream is the closest textual analog of the drawn model
this genre has found — a wire per name, barriers transforming the whole
bundle — and it is *the committee's semantic foundation*, not a feature:
they could not define grouping or windowing without first inventing our
wires.

One clash inside the convergence, load-bearing for the crossing round. A
`group by` clause "rebinds **all** the variables in the input tuple
stream" — including constants. The spec's own pitfall: `$high-price`
bound to `1000` outside the group ends up, post-grouping, bound to the
sequence `1000 1000 1000`, and the query prints "greater than 1000 1000
1000." Their fix is to move the binding out of the FLWOR entirely. In our
vocabulary the problem cannot be written: an ancestor context's value is
*available* across a barrier by provenance's prefix rule
(`barrier-value-crossing-design.md` — availability, not transport), so a
constant never gets repackaged per group. Their bug class is our design
argument.

### 2. Implicit flattening — the anti-lesson

This is the round's sharpest differentiation datum, and it names the two
costs the record's explicit-join, multi-wire core is built to avoid.

**Their approach.** Both languages flatten by default. XQuery: sequences
cannot contain sequences, so every intermediate result is flat and
grouping structure survives only if immediately reified as an element.
jq: a filter's output is a flat stream; `.[]` splices; only explicit
`[...]` collection reifies. The consequence took XQuery a decade to pay
off. In the 1.0 use cases, "group books by author" is written as
`distinct-values` plus a *re-query of the whole input per key*:

```
for $last in distinct-values($a/last), ...
return <result> ... { for $b in /bib/book
                      where some $ba in $b/author satisfies ... } </result>
```

(XMP Q4; Q10's min-price-per-title is the same idiom.) The data is walked
once to learn the keys and once more per key — the group structure the
input's iteration already had is erased by flattening and then
*re-discovered by search*. XQuery 3.0 buys grouping back as the `group
by` clause; jq ships `group_by` as a builtin from the start. And the
window clause (§3) is the same purchase for adjacency: the window
variable `$w` is bound to a *sequence as a value* inside each tuple — the
one place XQuery lets nesting survive, invented precisely because the flat
stream had destroyed it.

**Our approach.** Join is explicit — a binary flow operation
(`lazy-stream-join-design.md`) — and nesting lives in drawn flow
structure: an uncollect inside an uncollect *is* the grouping, and a
collect at either level reads it off. The grouping-lost vs grouping-kept
distinction is already vocabulary (`lazy-stream-commute-design.md`'s
option analysis). This is the strongest external validation the
explicit-join stance has: two shipped relatives chose implicit
flattening, and both had to re-purchase, as special constructs, structure
our core never discards. The confirmation runs deeper than convenience —
their grouping constructs are *recognizers* for structure the program
implicitly had, where ours is structure the program visibly kept.

### 3. The window clause — split-when shipped as a W3C standard

The round's richest section. XQuery 3.0/3.1's window clause is a
standards-track implementation of the segmentation territory
`variable-rate-consumption-design.md` owns, and it maps onto split-when
closely enough to serve as a full confirmation sweep — with three pieces
of structure the record does not yet have.

**Their construct.** `for tumbling window $w in E start ... when C1 end
... when C2` iterates the binding sequence and cuts windows: the start
condition identifies a start item, the end condition the first subsequent
item satisfying it; the window binds up to nine variables — the window
sequence itself plus, for each boundary, the item, its position, and its
**previous and next neighbors** (`start $s at $spos previous $sprev next
$snext when ...`). Both conditions see the start-side bindings; the end
condition sees both sides. `sliding` differs in one word: every item
satisfying the start condition opens a window, so windows overlap.

Mapped against split-when, one piece at a time:

- **The core is the same construct.** A tumbling window with a
  data-driven start condition is split-when: segmentation of one walk by a
  per-firing condition, each segment carrying its own state and collects.
  The spec's flagship — find "run-ups" in a price stream (`start $first
  next $second when $first/price < $second/price end $last next $beyond
  when $last/price > $beyond/price`) — is adjacency segmentation,
  split-when's ground.

- **The boundary-destination setting, dissolved into bindings?**
  Split-when's open question 1 is a three-value knob (boundary element
  starts next segment / ends current / is dropped). The window clause has
  *no knob* — instead the conditions read the neighborhood
  (`previous`/`next` bindings), and each destination is a phrasing. The
  use cases show all three: the implicit-section query puts the `<h2>`
  *outside* the window but reads its value through the binding (the
  delimiter reading, boundary value riding into the segment's readout);
  the dt/dd glossary query ends *inclusively* on the last `<dd>` (current
  in, successor out); run-ups starts each window *on* the firing that
  begins the rise. This is another wild sighting of the destination
  enumeration — and the first that is not an enumeration at all. A real
  input for question 1: instead of a three-value setting, expose the
  boundary firing's neighborhood and let the condition's operand say which
  side the cut falls on. Whether that is a dissolution or just the general
  form the three-value setting compiles to is the design conversation's
  call (nine bindable variables is a lot of surface — the knob is
  smaller).

- **`only end when` — the unterminated-final-segment bit. New
  dimension.** "If a start item is identified, but no following item
  satisfies the WindowEndCondition, then `only` determines whether a
  window is generated": without `only`, the trailing partial window is
  emitted (ended by end-of-input); with it, dropped. Both are everyday:
  fixed-size chunking emits the short last row; the Anton/Barbara query
  (§4) must *drop* an unterminated pattern. Split-when's round has the
  destination bit and the empty-segments question but nothing about the
  suffix when input ends mid-segment; end-when's inclusive/exclusive bit
  is adjacent but distinct (that decides a *found* boundary's side; this
  decides a segment whose boundary *never came*). Handed to the
  variable-rate round as a new enumerated choice, decided jointly with the
  destination bit.

- **Gap-tolerant segmentation — a variant with a field client.** Tumbling
  windows need not partition: items before the first start, and items
  between an end and the next start, belong to *no* window. Split-when as
  worked is a partition — every firing lands in exactly one segment. The
  scan-for-sync-then-consume shape (the datagram parser's framing, already
  a worked program) is precisely segmentation-with-rejected-residue; the
  window clause is evidence it is one construct with the partition case,
  selected by whether a start condition exists. Handed to the same round.

- **Sliding windows — overlap as a mode, and window(k) locates itself.**
  `sliding` turns the same clause into overlapping segmentation. The
  fixed-size instance is exactly the record's window(k) candidate
  (`translation-exercise.md` finding 9 — the pairwise B6 program *is* a
  sliding window of 2), and the use cases show the general form earning
  its keep beyond fixed k: moving averages (`only end at $e when $e - $s
  eq 2`), and outlier detection over a *time-bounded* trailing
  neighborhood. So window(k) is not its own construct — it is the
  (start-everywhere, count-bounded) point in a two-axis family
  (tumbling/sliding × condition/count-bounded) whose other points have
  field demand too. Handed jointly to the window(k) candidate and the
  variable-rate round.

- **Fixed-length segments by positional condition.** The
  chunk-into-rows-of-three use case writes the count as data on the
  position bindings: `start at $x when true() end at $y when $y - $x = 2`.
  Prior art for the fixed-length-segment catalog question (split-when
  question 4), consistent with the Raku round's finding that counts belong
  in the recognition spec as data, not as verdicts.

- **Segments-with-readout, confirmed again.** Each window tuple carries
  the segment as a value plus its boundary payloads — the
  per-segment-value-at-discharge skeleton, another independent
  confirmation after Ruby, Raku's `make`/`made`, and end-when's readout.

### 4. The event queries — recognition vocabulary's everyday list, and end-reasons by side-flag

**Their approach.** The 3.0 use cases' windowing suite is mostly not data
chunking — it is complex-event recognition over event streams, and reads
as a standards committee's own list of what stream programs are for.
Sessionisation of document sections (heading-then-paragraphs); dt/dd
phase grouping; "notify when Barbara enters within 1 hour after Anton":

```
for tumbling window $w in $seq/stream/event
  start  $s when $s/person eq "Anton" and $s/direction eq "in"
  only end $e next $n when xs:dateTime($n/@time) - xs:dateTime($s/@time) gt
    xs:dayTimeDuration("PT1H")
    or ($e/person eq "Barbara" and $e/direction eq "in")
    or ($e/person eq "Anton" and $e/direction eq "out")
where $e/person eq "Barbara" and $e/direction eq "in"
return <warning .../>
```

per-person working time (pair each "in" with the same person's "out", via
a sliding window whose end condition re-tests `$s/person eq $e/person`);
"Barbara did not come to work" (daily tumbling windows + absence test).

**Our approach.** Three rows get evidence:

- *The grammar reading is confirmed at standards level.* The Raku round
  conjectured that event handling is often grammar-shaped (phase-sequenced
  recognition with state). When a committee sat down to justify stream
  windowing, more than half its use cases were phase-sequenced
  recognitions over event flows — gestures' cousins (enter/leave pairing,
  timeout patterns, session boundaries). The demand list matches the
  grammar ladder rung for rung. (Not the owed UI sample — curated — but a
  strong prior.)
- *End-reasons reconstructed from side flags, in a spec.* The
  Anton/Barbara end condition is a disjunction of three reasons (timeout,
  Barbara-in, Anton-out), and the query must then re-test `where
  $e/person eq "Barbara"` to learn *which* reason fired — exactly the
  diagnosis survey 3 recorded for hand-rolled races ("every hand-rolled
  race reconstructs the winner from side flags"), which end-when answers
  with the terminator's discriminated readout. A W3C use case exhibiting
  the re-test idiom is the strongest outside witness yet that the
  fired-reason must be an output of the construct, not a fact the consumer
  re-derives.
- *Keyed partition wants to compose with segmentation.* The working-time
  query strains: lacking a per-key lane, it slides a window from every
  "in" event and lets the end condition filter for the same person — a
  quadratic-flavored scan encoding "group by person, then pair phases
  within each group." The natural drawn form is a keyed partition feeding
  a per-key split-when. Evidence that the keyed collect (§5) and
  segmentation are one composition, not separate worlds.

### 5. group by — the keyed collect's shipped form: groups are flows, not merged scalars

**Their approach.** XQuery's `group by` partitions the tuple stream by
key equivalence, and then: "each non-grouping variable is bound to a
sequence containing the concatenated values of that variable in all the
pre-grouping tuples assigned to that group." The spec's note contrasts
SQL: "SQL reduces the equivalent of a non-grouping variable to one
representative value ... In XQuery, each group is a sequence of items ...
further structures can be built based on the items in this sequence."
Aggregation is then ordinary downstream code (`sum($revenue)`,
`count($c)`); HAVING is a plain `where` after the group; hierarchical
reports are nested FLWORs consuming the group sequences. jq's `group_by`
is the same choice: an array of groups, aggregation applied after.

**Our approach.** The keyed collect is a standing open (the collect
family's spelling-and-identity round; the Flix round's `insertWith`
cluster). This corpus decides a structural fork the Flix sightings could
not: Flix's form merges per key by an operator (`insertWith(⊕)`),
XQuery/jq's form keeps each group *whole* — and the XQuery form is the one
that builds (principle 7): group-as-flows admits any downstream
consumption (+1 an aggregation, +1 a filter on groups, +1 a nested
report), where operator-merge is a single fused point. In drawn
vocabulary the XQuery form is the natural one anyway: a keyed partition is
a bundle whose cells are *data-determined* (contrast the case split's
static alts), each cell a flow; every value wire entering the barrier
corresponds, on the far side, to a per-group flow of its firings — which
is precisely what "non-grouping variables become sequences" says, minus
§1's constant-rebinding bug. The operator-merge form is then the fused
special case (a per-group collect chosen at the barrier), which is also
what shortest-distance-as-keyed-min-collect needs (saturation row).

Handed to the collect family's round as its likely primary/derived split,
with the dynamic-alt-set question flagged: bundles so far have statically
drawn cells; a keyed partition's cells exist only at runtime, so its
"bundle" is a different animal — per-key *lanes* (the tough doc's
keyed-lanes vocabulary arriving on the data side).

### 6. Running state and sources — foreach ships the running view; XQuery's missing scan is the negative witness

**Their approach.** jq's `reduce EXPR as $x (init; update)` is the fold
collect; `foreach EXPR as $x (init; update; extract)` is the *scan with a
readout* — per firing, update the state, then emit `extract` of it. The
manual's expansion makes it exactly the augment form: same walk, state
threaded, one output per firing. The Cookbook uses it as its
state-machine workhorse: running counters, adjacent-dedup (`uniq(s)` —
"emit `$x` iff it differs from the previous"), the `foreach (inputs,
null)` end-of-stream sentinel trick, and both streaming-parser recipes.
Self-driven sources are the other half: `while(cond; update)`, `until`,
`repeat`, `recurse(f; cond)` — seeded iterate-until constructs, all
defined in `builtin.jq` by recursion plus the comma operator, i.e.
hand-built from the language's assembly layer.

XQuery has **no scan at all**. FLWOR clauses can filter, reorder, number,
group, and segment the tuple stream, but no clause carries a value from
one tuple to the next; running totals require a recursive function, and
the use cases quietly route around the gap (the moving-average query
exists because *sliding windows* exist — a windowed mean is the
scan-shaped query you can still write when you have windows and no
register).

**Our approach.** Confirmation on three counts, no new structure:

- `foreach` is the running view of a collect — the state port of the
  derived augment form (`variable-rate-consumption-design.md`, Part II) —
  shipped, named, and everyday in field-like code; its `(init; update;
  extract)` shape is the augment form's exact port list.
- The missing-scan mirror: a dataflow language that ships without
  loop-carried state bends its other constructs (windows, recursion
  escapes) around the hole — outside witness that the register row is
  load-bearing for this class of language, which is already its W 5.
- `while`/`until`/`repeat`/`recurse` are the self-driven source opener,
  hand-built — a further independent witness on the concurrency row's
  source-opener item. jq's `input`/`inputs` add the *pull-based FFI
  source* (the other source-opener species the translation exercise
  named): "outputs one new input" from an outside the language does not
  model.

### 7. Paths as values — focused update, the second genuinely missing construct

**Their approach.** Half of jq answers one question the record has never
asked: *how do you change a small part of a large nested value?* The
mechanism: every filter, evaluated in path context, denotes the list of
locations it selects; assignment operators take a filter on the left and
rebuild the input functionally at those locations — "whichever paths it
selects from the input will be where the assignment is performed."

```
(.posts[] | select(.author == "stedolan") | .comments) |= . + ["terrible."]
(..|select(type=="boolean")) |= if . then 1 else 0 end
reduce paths as $p (.; if getpath($p)|... then setpath($p; ...) else . end)
```

Selection vocabulary and update vocabulary are the *same* vocabulary;
paths are first-class data (`path(f)`, `paths`, `getpath`, `setpath`,
`delpaths`); deep rewrites compose with recursion (`walk`,
`recurse(.children[]) |= del(.foo)`). And XQuery, lacking this, exhibits
both the assembly language and the bolt-on. The assembly language is the
spec's own appendix — the `swizzle` typeswitch recursion, which rebuilds
*every* node of the tree by cases to change the few that match: the
identity-transform boilerplate that is to tree rewriting what the flag was
to end-when and the worklist to saturation. The bolt-on is an entire
second W3C facility (§8) whose `copy ... modify ... return` exists to say
"a changed copy of this tree" at all.

**Our approach.** Nothing owns this, and it is not close to anything that
does. The trees row is narrative-stage and its concerns are iteration and
construction; the partial collect edits flows, not resting structure;
`transformation-levels-design.md` edits *programs*, not values. Stated in
our vocabulary, the shape is: **uncollect a path down to the loci,
transform there, and re-collect upward with every untouched sibling
passing through unchanged** — the identity-recursion is what that
composition costs when written by hand, at every level of the structure,
which is exactly the "assembly language" test the record uses to
recognize a missing construct. Three observations travel with the demand:

- jq's deepest design win is that *selection and update share one
  vocabulary* — the same filter that reads a locus writes it; any drawn
  form should preserve that identity rather than inventing a separate
  update-side language.
- A path is a drawable witness of a locus — this connects to provenance
  and to `types-design.md`'s witness instinct, and jq's `paths`-as-data
  programs show the reflective tier (compute *which* loci from the data
  itself) is everyday, not exotic.
- The multi-locus case is primary, not an extension — `(.a, .b) = 0`,
  `(..|select(f)) |= g`, and the every-matching-node rewrites are the
  common uses.

Evidence honesty: the loop surveys could not have seen this shape (it is
not a loop), and this round's corpora are domain-biased toward it (reading
rule 4); but two shipped relatives independently building major machinery
for it — one as half its language, one as a separate standards facility —
is the genre's strongest convergence signal, and the shape's imperative
costume in general code (the spread-pyramid / builder-copy idiom for
updating nested immutable state) is common enough to deserve the frequency
question. New open problem; the frequency sample owed.

### 8. The pending update list — effects as collected values, shipped

**Their approach.** XQuery proper is pure. The Update Facility adds
updating expressions with a deliberately non-imperative semantics: "A
**pending update list** is an unordered collection of update primitives,
which represent node state changes that have not yet been applied."
Evaluating `insert`/`delete`/`replace`/`rename` *performs nothing*; it
accumulates primitives, merged up the expression tree by the ordinary
evaluation machinery, and the whole list is made effective at once at the
end of the query — with declared compatibility rules deciding conflicts
rather than execution order (the collection is *unordered*). Within the
snapshot, reads never see writes. The `copy $c := E modify U return R`
form scopes the same machinery to a fresh copy, giving pure
tree-transformation.

**Our approach.** The Tier-1 IO/effects row has, until now, received only
confirmations from this genre ("their examples interleave effects; ours
can't"). This is the first *structural* prior art: a shipped language in
our own family answering per-firing effects by making the effect a
**value** — collected by ordinary flow machinery, discharged at a barrier
at the end, ordering resolved by declared rules rather than by when code
ran. That is recognizably one of the candidate shapes the record's
effects conversation will have to weigh (effects-as-collected-plan vs
effects-as-sequenced-thread — the IO-thread leaning in
`tough-use-cases-design.md` is the other pole), and its strain points are
field data on questions the row already carries: no read-your-writes
inside the snapshot (fine for document patching; wrong for interactive
IO), and the conflict/compatibility rules are where "effect ordering
within a firing" resurfaces once execution order is renounced. jq sits at
the same pole even more simply: effects only at the edges (`inputs` in,
output stream out, `debug` as the lone sanctioned leak) — a pure core is
viable *as a tool* because the shell around it is the effectful skeleton.
That exit is not open to us — our language wants to be the host, not the
guest — which is itself worth recording: the pure-pipeline family's most
common answer to effects is to make them someone else's problem.

### 9. Ordered choice and backtracking over pure values — the speculation row's shipped cousin

**Their approach.** jq is quietly a nondeterministic language:
expressions denote value streams, `empty` "backtracks to the preceding
generator expression," alternatives are just streams (`.[]?`, `//`,
`?//`, `try/catch`), and commitment is `first`/`limit` — implemented in
`builtin.jq` with a lexical label: `def first(g): label $out | g | .,
break $out;`. There is **no state-restoration machinery anywhere**,
because there is nothing to restore: an abandoned alternative is a value
stream nobody consumed further.

**Our approach.** The speculation row's recorded leaning is exactly this
("consumed input threaded as positional values so restoration is
structural rather than semantic"), argued until now from Effekt's
counterexample and Raku's ratchet default. jq is the positive witness: a
shipped language whose entire alternatives-and-failure story runs on pure
value streams with zero rollback — at the cost of owning no
*consumed-input* notion at all (jq never parses; its backtracking is over
derived values, which is why it gets this for free — noted so the row
doesn't over-claim). One clash travels with it: `//` triggers on the left
side producing "no values other than `false` or `null`" — a conflation of
*no firings* (flow-level absence) with *falsy value* (value-level
content) that the manual and FAQ then spend paragraphs disentangling. Our
value/flow wire sort makes the conflation unwritable — the option flow's
fires-or-not is not a value — and jq's documentation burden is the
evidence that keeping them distinct is worth two wire sorts.

### 10. Smaller sightings

- **`count` + `where` as top-N.** `order by $p/sales descending count
  $rank where $rank <= 3` — reorder, number, filter as three ordinary
  stream barriers. But note it does not *stop* — termination is the
  optimizer's mercy, there being no end-when. jq's `limit` is the honest
  version (it actually aborts, via `label`).
- **`order by` and `sort`.** A reordering barrier on the tuple stream
  (all wires pass through), with configuration exactly where
  `configuration-scopes.md` puts sort's comparator (collation,
  empty-least/greatest, stable — node-attached configuration). XQuery 3.1
  also ships `fn:sort($seq, $key-fn)` — barrier form and function form
  coexist.
- **`allowing empty` — the outer join.** A for clause that fires once
  with an empty binding on an empty sequence, "similar to that of an
  'outer join'": the fires-or-not option flow given a fired-empty
  completion so downstream tuples survive. Adjacent to the partial
  collect's territory.
- **Document order and `<<`.** Path steps return distinct nodes in
  document order — dedup plus a canonical order derived from *source
  provenance*, not computation order; `$book1 << $book2` uses it to
  canonicalize unordered pairs. Prior art that a provenance-derived
  canonical order is a coherent, useful law — and a mild clash (it is an
  invisible global invariant; ours would need to be a drawn/stated
  property).
- **PARTS and TREE — recursion confirmations.** The part-explosion use
  case (flat parent-child records → nested tree, by recursive function
  with an embedded per-level query) and the recursive TOC are the divide
  flow's everyday clients again, this time data-side. The `$s/@partof =
  $p/@partid` recursion is also saturation's top-down dual in miniature.
- **`tostream` — trees as provenance-tagged flows.** The streaming parser
  turns a document into a flow of `[path, leaf]` events, and the FAQ's
  programs over it are hand-built phase recognizers (state machines over
  path prefixes — the grammar shape again, in the least likely corpus). A
  tree serialized as a flow *with its provenance attached* is a suggestive
  datum for the trees row's eventual flow story.

## The yield

**The headline.** Read as one signal, the two shipped members of our own
family:

- **confirm the core exactly where the record bet** — explicit join and
  drawn nesting (§2); multi-wire barriers (§1); values-not-rollback (§9);
- **ship standardized versions of three open candidates**, each landing
  on an existing row as a confirmation sweep with new structure — windows
  → split-when (§3), group by → keyed collect (§5), foreach → running
  view (§6);
- **expose two territories where both built major machinery the record
  has no row for** — changing part of a nested value (§7) and effects as
  collected values (§8).

The direction reading: the open-problems ranking survives contact almost
unchanged, with one new row and the Tier-1 effects row gaining its first
structural prior art. The detailed findings:

- **The tuple stream is independent arrival at
  barriers-not-bottlenecks.** FLWOR's semantic foundation is named
  multi-wire tuples flowing through clause barriers; jq's single-value
  pipe is the counterexample, paying `as $x` bindings and packed objects
  at every two-value step. Confirmation for the no-bottlenecks principle
  and the crossing round; one clash — the group barrier rebinding
  *constants* into per-group sequences is a bug class our
  availability-by-provenance rule makes unwritable.
- **Implicit flattening is the anti-lesson.** Both relatives flatten by
  default; both re-purchased grouping as special constructs (the `group
  by` clause after a decade of `distinct-values`-and-requery; the
  `group_by` builtin; the window variable binding a sequence-as-value
  because flat streams destroy adjacency). Strongest external validation
  yet for explicit join and nesting-as-drawn-structure. No score movement
  (the core is not an open problem), but the round's sharpest
  differentiation datum.
- **The window clause is split-when's confirmation sweep, plus three new
  pieces of structure.** Same core construct (data-driven boundary
  segmentation with per-segment readouts). New for the variable-rate row:
  (a) the boundary-destination knob's possible dissolution into
  *neighborhood bindings* on the condition; (b) the
  **unterminated-final-segment bit** (`only end when`): emit-partial vs
  drop when input ends mid-segment — a new enumerated choice, decided with
  the existing destination bit; (c) **gap-tolerant segmentation** (windows
  need not partition; scan-for-sync framing is its field client). Sliding
  windows locate window(k) as the fixed-size point of a two-axis family
  (overlap × how bounded); positional end conditions answer the
  fixed-length catalog question. Owner:
  `variable-rate-consumption-design.md`, with the window(k) candidate
  folded into the mapping.
- **Event recognition is windowing's everyday client, and end-reasons are
  reconstructed from side flags even in a spec.** The 3.0 windowing use
  cases are mostly complex-event recognition, matching the grammar ladder
  rung for rung (strong prior for the Raku round's question; the owed UI
  sample still decides). The Anton/Barbara query's three-way end
  disjunction re-tested in `where` is the strongest outside witness yet
  for end-when's discriminated terminator readout. The per-person pairing
  query's quadratic strain is evidence that keyed partition must compose
  with segmentation.
- **The keyed collect's shipped primary form is group-as-flows.**
  "Non-grouping variables become sequences"; aggregation, HAVING, and
  hierarchical reports are all ordinary downstream consumption of the
  group flows — the form that builds (+1 steps check passes), against
  which Flix's `insertWith` operator-merge is the fused special case. A
  keyed partition is a bundle with *data-determined* cells — per-key lanes
  arriving on the data side, distinct from the static-alt case bundle.
  Handed to the collect family's round as its candidate primary/derived
  split.
- **The running view is shipped (`foreach`), the scan's absence bends a
  language (XQuery), and the source opener gets a further witness.**
  `foreach (init; update; extract)` is the augment form's port list,
  everyday in the corpus's most field-like code; XQuery, with no scan
  clause, routes running-state queries through windows and recursion — the
  negative witness that the register row is load-bearing for this language
  class. `while`/`until`/`repeat`/`recurse(f; cond)` are the self-driven
  source opener hand-built from recursion; `input`/`inputs` are the
  pull-based FFI source.
- **Focused update: transform selected loci of a nested value, preserving
  the rest. New open problem.** Half of jq (paths as first-class values;
  every assignment defined by LHS-selected paths; `walk`-family rewrites)
  and a whole separate W3C facility (Update; `copy...modify...return`)
  answer a shape the record has never asked about, whose hand-written form
  (XQuery's `swizzle` identity-recursion — rebuild every node to change a
  few) is the standing assembly-language diagnosis in another costume. In
  our vocabulary: uncollect down to the loci, transform, re-collect with
  untouched siblings passing through. Scope items: selection and update
  sharing one vocabulary (jq's deepest win); paths as drawable witnesses
  of loci; multi-locus as the primary case; the tree-rewrite connection to
  the trees row. Invisible to the loop surveys by construction,
  domain-overweighted here; frequency question owed. Proposed row: I 5, W
  3, with the sample deciding any W move.
- **The pending update list is the effects row's first structural prior
  art.** A shipped relative answers per-firing effects by reifying them:
  unordered collection of update primitives, gathered by ordinary
  evaluation, applied atomically at a snapshot barrier, conflicts resolved
  by declared rules — the effects-as-collected-plan pole of the design
  space, with its strain points (no read-your-writes; conflict rules are
  where within-firing ordering resurfaces) mapping onto the row's existing
  questions. jq marks the same pole degenerately (effects only at the
  edges — viable for a guest tool, not for a host language). Handed to the
  Tier-1 row as structure, not a design.
- **Confirmations, briefly.** jq's zero-rollback nondeterminism (streams +
  `empty` + `first`-commits) is the shipped positive witness for the
  speculation row's threaded-values leaning — with the caveat that jq owns
  no consumed-input notion. `limit`/`label`/`break` are end-when/take with
  a lexical label; XQuery's `count $rank where $rank <= 3` filters without
  stopping. `order by` is a reordering barrier with node-attached
  configuration exactly where `configuration-scopes.md` puts sort's
  comparator. `allowing empty` is the outer-join completion of a
  fires-or-not flow. PARTS/TREE recursion and jq's `walk` are the divide
  flow's data-side everyday clients; `tostream`'s path-tagged event flow
  is a suggestive tree-as-flow datum. Document order is prior art for a
  provenance-derived canonical order.

## The clash record: what must not be imported

Not criticisms — the reasons a graft fails, and in this round's case,
mostly reasons the record's existing commitments are right.

- **The implicit context value** — jq's `.` is an invisible wire with
  magic-name flavor; one free wire forces packing for all others (the
  bottleneck as a mechanism, §1).
- **Implicit flattening** — join-by-default erases structure that must
  then be re-recognized by special constructs (§2).
- **Cartesian products by adjacency** — "at the drop of a hat,"
  multi-valued operands multiply silently; the community pitfall page is
  the receipt. Our products are a drawn Cross.
- **`//`'s empty/falsy conflation** — flow absence and value falsiness
  folded into one operator, then disentangled across paragraphs of
  documentation; the value/flow wire sort forbids writing it.
- **The group barrier rebinding everything** — constants becoming
  per-group sequences (the `1000 1000 1000` pitfall);
  availability-by-provenance is the answer.
- **Canonical order as invisible global invariant** — document order is
  useful but readable nowhere at the use site; ours would be a stated,
  drawn property.

Read together, the first two clashes are the anti-lesson at the center of
this round: **implicit flattening and the single-context-value bottleneck
are the two costs the record's explicit-join, multi-wire core exists to
avoid** — and both cost their languages real machinery to buy back.

## What this study changes in `open-problems.md`

- **New Tier-2 row**: focused update — transform selected loci of a nested
  value, preserving the rest. I 5 (a name and a demand, nothing worked), W
  3 (two shipped relatives built major machinery; invisible to the loop
  surveys by construction; the frequency sample decides any move).
- **Variable-rate consumption row**: the window-clause sweep — the
  neighborhood-bindings input to question 1, the new
  unterminated-final-segment bit, gap-tolerant segmentation, window(k)
  located as a family point, positional counts for question 4; plus the
  keyed×segmentation composition note. Scores unchanged; the remaining
  list is sharper.
- **IO/effects (Tier 1)**: the pending-update-list structural note — first
  prior art, not a confirmation. Scores unchanged (nothing designed).
- **Loop-carried state row**: `foreach`-as-running-view and the XQuery
  negative witness; group-as-flows to the collect family's joint round.
  Scores unchanged.
- **Concurrency row**: a further source-opener witness plus the pull-based
  FFI source sighting. Scores unchanged.
- **End-when (Tier 3)**: the side-flags-in-a-spec witness and the
  no-stopping `count`/`where` contrast. Scores unchanged.
- **Speculation row**: the shipped threaded-values witness with its
  no-consumed-input caveat. Scores unchanged.
- **Evidence owed**: the focused-update frequency question — a sample of
  application code's nested-immutable-update idioms (spread pyramids,
  builder copies, `setIn`/lens libraries) measuring how often the shape
  occurs outside document-processing domains.

## Next rounds of this genre

This study retires the generic "dataflow language" slot. Remaining
candidates: the **reactive-library round** (Rx/signals/FRP as used from
host languages — split off because reading it well means reading
*library-using application code*, closer to the survey method than to this
genre); the **APL-family round** (the uncollect/collect story stress-read
from the array side — this round's grouping and windowing material gives
it specific questions); the **beginner-first round** (Scratch/HyperCard
lineage, where the discoverability bar is the whole language). The
uses-not-showcases variant applies to all three, and to this round's own
follow-up: real jq programs in build scripts and real XQuery in document
pipelines would supply the field sightings this curated corpus cannot.
