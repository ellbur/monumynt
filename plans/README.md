
OH Comment: Generally in this file, conider whether the brief descriptions
that follow linked files are understandable to a newcomer. A lot of them
use historical jargon like "Option C was chosen," when the reader is
going to have no idea what "Option C" was.

# Design documents

This is the design record for an experimental visual, flow-based
programming language. The docs range from settled foundations to
bleeding-edge exploration; read the two fundamentals first, then follow
the map below to whatever you're after.

Each entry says what the doc is about and where it stands. A few
recurring status words:

- **implemented** — true of the code in `src/` today.
- **adopted** — a settled design decision, not yet all built.
- **exploration** — a worked proposal with leanings, prepared for a
  design conversation but *not* adopted. Read these as "here is a
  candidate and the case for it," not "here is the answer."
- **deferred** — a real design that is parked as a later optimisation,
  *not* rejected.
- **rejected / dissolved** — an idea we decided against. Rejected ideas
  are recorded **in place**, in the doc that owns the topic, together
  with the reason they must not be tried again. Check those before
  re-proposing a construct.

OH Comment: The following are too detailed to be listed up front
here. The reader won't even know what they mean. They only need
to be listed in the specific docs where they are relevant.

Four statuses are easy to misread, so, stated once: the compile-time
placement pass and the stream consumer-set lattice are **deferred
optimisations, not rejections**; the two iteration-state candidates are
**both still live**; **Incorporate is a live primitive** (only its
sibling-opens use was corrected to Cross); pure-pull for incremental
flows is a **first-implementation convenience, rejected for the long
term**.

## Start here — the fundamentals

Everything else hinges on these two:

OH Comment: In the below, I'd change "no time travel" to
"(no) time travel" to reflect that time travel is now very much
part of the language the user will program in, while being
always transformed to no time travel to show the user what will actually happen.

- **[`language-design-philosophy.md`](language-design-philosophy.md)** —
  the seven principles every new construct is judged against, and the
  standing method (sample real code) that keeps the design honest.
- **[`core-model.md`](core-model.md)** — the core in current vocabulary:
  value wires vs flow wires, uncollect/collect, no time travel, join,
  bundles, barriers-not-bottlenecks, and the table of flow kinds.

## The language description

- [`visual-language-spec.md`](visual-language-spec.md) — the
  data-representation spec: diagrams, nodes, ports, value vs flow wires,
  Delay.
- [`textual-representation-design.md`](textual-representation-design.md)
  — the parseable/printable textual form the other docs write examples
  in: sorted arrows (`->`, `~>`, `-~>`), postfix chains, ports and
  projections, taps, marks, and lanes, registers. If you want to *read the code
  samples* in the rest of the record, skim this first.

OH Comment: We need to decide what to do with the following. No sense
keeping them around for historical reasons. If they have useful points
on language philosophy, they should go there. If they have ideas 
worth developing, they should be developed.
  
- Short topic docs distilled from the retired first-generation
  narratives: [`trees-and-recursion.md`](trees-and-recursion.md),
  [`functions-design.md`](functions-design.md),
  [`custom-flows.md`](custom-flows.md),
  [`configuration-scopes.md`](configuration-scopes.md).
- [`facets-design-notes.md`](facets-design-notes.md) — early, deliberately
  undeveloped intuitions about *facets*: authorable, attachable
  abstractions (interfaces, algebras, state machines) you hang on code.
  Extends the facets material in `tough-use-cases-design.md`.

## The biggest open area

- **[`iteration-with-state-design.md`](iteration-with-state-design.md)**
  — loop-carried state (running sums, accumulators, anything a loop
  updates as it goes). Two candidate surfaces are proven to compute the
  same results; the open question is which drawing is primary. The bar:
  easy for beginners *and* flexible enough for complex code. Start with
  the reader's guide at the top. Companions:
  [`iteration-rails-design-notes.md`](iteration-rails-design-notes.md)
  (the redesigned "rail" surface) and the Delay back-edge sections of
  `first-class-ports-design.md`.

OH Comment: first class ports design shouldn't be a main topic page for
iteration with state design. It's a separate topic. Reorganize this info across these pages.
  
- **[`delay-ontology-design.md`](delay-ontology-design.md)** — the open
  problem split out of the doc above, kept whole here: what a Delay *is*,
  and which flow supplies its "next iteration." The collect-vs-ancestor
  fork dissolves on sequences and is silent on grids (the value-in-context
  model); the candidates answer the register's two halves (update cadence
  vs read range — this is `hold`); the live residue is a product's
  linearization, plus the per-kind "next iteration" question that several
  rounds (incremental, concurrent collect, effects) are already writing
  checks against.

## Representation and checking

OH Comment: first class ports should become such a basic aspect of the
language that we no longer need a doc devoted to it. It's like in a
book on C, you wouldn't have a chapter on structs and then a second
chapter on structs having more than one field. It's basic to the
language that nodes have multiple ports. Maybe the other docs aren't
there yet, but they should get there, and info in the first class
ports design page moved into other pages or deleted.

- [`first-class-ports-design.md`](first-class-ports-design.md) — the
  next representation step: making ports first-class, which dissolves the
  Branch node and the flowRef wrapper stack, and adds the Delay write
  half. Also: "the program is a node set" (not a root expression). First
  on the implementation path.
- [`barrier-value-crossing-design.md`](barrier-value-crossing-design.md)
  — one place to answer how values cross barriers (joins, races, partial
  collects), a question several docs had deferred to each other. Two
  mechanisms plus a co-location rule. *Exploration.*
- [`types-design.md`](types-design.md) — validity without a type system:
  properties that propagate along wires, witnesses you can draw, no
  search.

OH Comment: The below summary of that doc is entirely opaque to someone
who doesn't know the language yet. Try to reword it in a way that is
more generally understandable to an outsider.

- [`bundle-provenance-design.md`](bundle-provenance-design.md) — context
  paths, and the one check that catches two kinds of clash (mixing
  mutually-exclusive case branches; time travel).

## Editing

- [`program-editing-design.md`](program-editing-design.md) — how
  programs are edited (first vehicle: a curses-style TUI over the
  textual form): the cursor as a node/port/slot position plus a mark,
  every edit an atomic pure function preserving structural validity,
  and holes/planned wires as the representable partiality that makes
  that possible. Builds on the step-DAG and completion docs.
  *Exploration.*

## Constructs

OH Comment: Should the below doc maybe be categorized along with other
case-split related docs?

- [`partial-collect-design.md`](partial-collect-design.md) — collecting
  only some branches of a case split; one k-ary partial-collect node.

- [`product-flows-design.md`](product-flows-design.md) — Cross, the node
  for combining two independent (sibling) flows without nesting one in
  the other; commute-as-transpose over products. Also its positional
  sibling, the aligned product (zip) — same-extent pairing by position —
  and the multi-wire collect (the table) as zip's value form.

OH Comment: I think the below doc on time-travel should be moved to a place that reflects it is
more fundamental than some of the other docs. It's basic to the nature
of the language.

- [`time-travel-programs-design.md`](time-travel-programs-design.md) —
  letting you draw under-committed programs (order left unstated) and
  having the editor complete them by published rules, shown faint.

OH Comment: The below doc on transformation levels is also fundamental, but it's
sort of a reach goal.

- [`transformation-levels-design.md`](transformation-levels-design.md) —
  program and edit history as one structure; every lowering is a
  read-only derived view; nothing is ever mutated.

OH Comment: The below two docs (end when and variable rate consumption) seem to belong
to a similar concept space, which is more flexible iteration.

- [`end-when-design.md`](end-when-design.md) — data-driven termination
  (stop the loop when the data says so): the surveys' biggest unserved
  everyday demand, worked as a binary flow operation. *Exploration.*
- [`variable-rate-consumption-design.md`](variable-rate-consumption-design.md)
  — "advance how far?" reframed as placing segment boundaries
  (split-when), plus the running view of a collect. *Exploration.*

- [`source-openers-design.md`](source-openers-design.md) — flows with no
  input list (`repeat`, self-driven loops, external pull sources), plus
  pacing (gate the next firing on an async value). The most-witnessed
  unowned item in the surveys. *Exploration.*
- [`collect-family-design.md`](collect-family-design.md) — the empty
  collect (what does an empty sum/max return?), identities as catalog
  rows, and the keyed collect (group-by as flows). *Exploration.*

OH Comment: The below doc summary is very opaque to an outsider.

- [`speculation-design.md`](speculation-design.md) — ordered alternatives
  with rollback (try-in-order choice for parsers and search): race's
  *sequential* sibling, where restoration is structural (the shared input
  wire, not a save/restore operation). *Exploration.*
- [`focused-update-design.md`](focused-update-design.md) — transform
  selected loci of a nested value, preserving the rest (increment every
  post's likes, redact one field): a structural selection read as a round
  trip, its write-back the derived mirror of the path (the lens); value-
  selected update is a case split with an identity branch, never a filter.
  *Exploration.*
- [`saturation-design.md`](saturation-design.md) — closure under rules
  (graph reachability, transitive closure, dataflow analysis): the
  register's dual one level up — a back-edge on a *flow* wire (a set
  collect re-opened) where the register is a back-edge on a *value* wire (a
  Delay). Naive vs semi-naive are lowerings; the lattice variant is the
  keyed collect under feedback. *Exploration.*

OH Comment: Just from the below summary, it's not obvious to me why an effect
that fires once per loop iteration is unwritable, since I would think that
would just be commuting the effect flow out of the loop flow?

- [`effects-design.md`](effects-design.md) — per-firing effects (cause an
  effect once per firing of a loop — the most common loop payload, and
  currently unwritable): the IO handle threaded through the loop *is* a
  register on a marker wire, so "collect of an effect flow" is the
  register's `final` (one handle out, not a list); a spanning handle
  threads and orders, a per-firing-minted handle is independent and
  commutes. The effects half of the IO row; within-firing
  ordering and the batched (collected-plan) pole are fenced out.
  *Exploration.*
- [`within-firing-effects-design.md`](within-firing-effects-design.md) —
  effect ordering *within* one firing, and the conditional-flush buffer
  (breadth item 5): within a firing there is no time — the only
  intra-firing order is along a handle's segment — and the buffer
  dissolves into a segmentation of the op flow (buffer = per-segment
  collect, reset = boundary, flush = per-segment write). Batching is
  meaning exactly when the sink's write doesn't coalesce (chunked
  encoding); a handle is an ordering commitment. *Exploration.*
- [`cancellation-design.md`](cancellation-design.md) — the other half of
  the IO row: cancellation and bracket. Stopping is drawn (race,
  interrupt, end-when); cancelling is *delivered* — the runtime writes a
  `Cancelled` terminator to in-flight work stranded by ceased demand,
  over the same necessity frontier the incremental flow uses, so there
  is no cancel token in the vocabulary. Bracket is the lifecycle segment
  plus a late-wired release half on the acquire (release on any end,
  keyed per terminator lane). *Exploration.*

## Flow kinds beyond lists

The one open/collect shape is instantiated per kind. Lists and
case/option are implemented; the rest are designed:

- [`commute-design-notes.md`](commute-design-notes.md) — the
  commute-on-lists analysis (a superseded stopgap kept for its options
  survey) that led to streams.

OH Comment: The below doc on lazy stream placement should really be under the
"Compile" heading beacuse it's about how to compile a stream flow. Also the
below description should not reference "Shape C" because the reader will
have no idea what "Shape C" is.

- [`lazy-stream-placement-design.md`](lazy-stream-placement-design.md) —
  stream flows (pull-based, on-demand). Read the status header: Shape C
  is the baseline; the consumer lattice is the deferred optimisation.

- [`lazy-stream-join-design.md`](lazy-stream-join-design.md) — join as a
  binary flow operation. This is the correction the whole record now
  follows.
- [`lazy-stream-commute-design.md`](lazy-stream-commute-design.md) —
  commute across stream flows; the commute-variant taxonomy.
- [`async-flow-design.md`](async-flow-design.md) — the async flow:
  values that arrive later, racing as a barrier, failure as a terminator
  payload.
- [`race-barrier-design.md`](race-barrier-design.md) — the race
  barrier's own semantics: first-to-settle wins, ties by drawn order,
  merge/interrupt/timeout as derived vocabulary. *Exploration.*

OH Comment: The below summary is very opaque to an outsider. The summary
should say what the concurrent collect generally is, what it is for, etc.,
not some obscure detail of how it's implemented.

- [`concurrent-collect-design.md`](concurrent-collect-design.md) — one
  primitive (settle) minting a completions flow: one firing per body
  that settles, in settlement order, failures carried as data.
  *Exploration.*

- [`incremental-flow-design.md`](incremental-flow-design.md) — the
  incremental flow (reactive vars): hold/changes, cutoff, and pushing
  values into a "necessity frontier."

## Compile

- [`lazy-compile-design.md`](lazy-compile-design.md) — the
  **implemented** runtime-lazy strategy in `src/Compile.res`.
- [`compile-strategy-design.md`](compile-strategy-design.md) — the
  planned rebuild: a pipeline of pure passes, same semantics.
- [`placement-algorithm-notes.md`](placement-algorithm-notes.md) — the
  retired compile-time placement algorithm; a hybrid revival is deferred,
  not rejected.

## Stress tests and evidence

The design is checked against real code two ways: deliberately hard
programs, and randomly sampled ordinary ones.

- [`tough-use-cases-design.md`](tough-use-cases-design.md) — five
  real-system programs pushed against the constructs until they break;
  the ranked inventory of candidate blocks that fell out.
- [`real-loop-survey.md`](real-loop-survey.md) — the sampling record:
  three seeded-random draws of real loops, classified against the
  inventory. Findings that reweighted the agenda: uncollect/collect is
  the center; early termination is the biggest everyday gap; the
  running-sum scan is rare in infrastructure but dominant in numerics;
  first-of coordination (race/timeout/cancel) outweighs all-of nine to
  one. Read the tallies with the 80/20 counterweight (frequency ranks
  what must be *effortless*; the rare painful case is a *breadth*
  obligation, never a reason to deprioritise).
- [`translation-exercise.md`](translation-exercise.md) — thirteen sampled
  loops transcribed into the textual form, trivial to hard. The core and
  the scans carried cleanly; the gaps it exposed (per-firing effects,
  source openers, the register write-half two-phase form, the collect
  family's spelling) became agenda items.

### Learning from other languages

Each of these reads another language's real programs against the record,
extracting *problems* (never mechanisms), and ends with a clash record of
what must **not** be imported and why:

- [`effekt-comparison.md`](effekt-comparison.md) — effect handlers.
  Yield: speculation (ordered alternatives with rollback) as a new open
  problem; demands for late-bound operations and the test double.
- [`raku-grammars-comparison.md`](raku-grammars-comparison.md) — grammars
  and regex, read as a special case of inhomogeneous iteration.
- [`flix-comparison.md`](flix-comparison.md) — first-class Datalog,
  effect-handler stdlib, channels, regions. Yield: saturation (closure
  under rules) as a new open problem; the policy/middleware layer.
- [`xquery-jq-comparison.md`](xquery-jq-comparison.md) — the family's two
  shipped dataflow relatives. Yield: focused update (transform selected
  loci of a nested value, preserving the rest) as a new open problem; the
  window clause as split-when's confirmation.
- [`apl-family-comparison.md`](apl-family-comparison.md) — the array
  languages, read to find shapes the drawn vocabulary struggles with.
  Yield: the aligned product (zip) as the one localized struggle; the
  operator catalog maps onto first-order constructs.
- [`reactive-comparison.md`](reactive-comparison.md) — Elm and the JS
  signal libraries. Confirms the incremental flow *is* the reactive-var
  core (the TC39 Signals proposal matches it point for point).
- [`zig-comparison.md`](zig-comparison.md) — imperative control flow
  redesigned. Zig's loop headers decompose into exactly the record's
  constructs (end-when + register write-half; `break v`/`else d` is the
  discharge readout as syntax).
- [`tidyverse-comparison.md`](tidyverse-comparison.md) — dplyr/tidyr/purrr.
  Answers "is a table more than a list of structs?" — yes: the data
  frame is the multi-wire flow at rest.

## Sequencing and open problems

OH Comment: From the below description, implementation-strategy.md sounds
like it belongs in the compile category.

- [`implementation-strategy.md`](implementation-strategy.md) — the map
  from the design record to code: workstreams, ledger, sequencing.

OH Comment: The below problems doc should be listed at the top of this README, since it spans everything.

- [`open-problems.md`](open-problems.md) — the ranked index of open
  problems and incomplete areas, scored incompleteness × importance.
  Read its anti-tunnel-vision rules before treating it as a queue.

## Layout (out of scope in this repo)

Kept because the layout algorithm should survive, but the graphical side
is out of scope for work here. Each carries a status header noting where
its vocabulary predates the newer rounds.

- [`graph-representation.md`](graph-representation.md)
- [`visual-layout-guidelines.md`](visual-layout-guidelines.md)
- [`rendering-algorithm.md`](rendering-algorithm.md)
- [`program-to-graph-transformation.md`](program-to-graph-transformation.md)

## Retired documents

OH Comment: If these docs are truly retired, no need to list them here.

`flow_language_design.md` and `visual-flow-language.md` — the
first-generation narratives copied from an older project — were retired.
Their live content is now in `core-model.md` and the topic docs above;
their superseded content is recorded briefly in the docs that superseded
it; the full originals are in git history. Citations to them in older
docs refer to that preserved record.
