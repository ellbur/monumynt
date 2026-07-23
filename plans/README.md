# Design documents

This is the design record for an experimental visual, flow-based
programming language. The docs range from settled foundations to
bleeding-edge exploration; read the two fundamentals first, then follow
the map below to whatever you're after.

The docs that describe the language itself are written in a tutorial
voice: each starts from the simplest program that shows its topic and
builds up, introducing concepts through examples. They remain the
authoritative design record — every decision, open question, and piece
of evidence is still in them. In particular, rejected and dissolved
ideas usually appear as "now, you might wonder why the language
doesn't…" passages, each carrying the full reason the idea must not be
tried again. The docs that are evidence and analysis rather than
language description — the surveys, the other-language comparisons,
the compile and sequencing docs — keep their plainer report style.

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

Each doc's own status header is authoritative for what in it is live,
deferred, or rejected — read it before treating anything as decided
either way (deferred is not rejected, and an unpicked candidate is not
a loser).

## Start here — the fundamentals

Everything else hinges on these two:

- **[`language-design-philosophy.md`](language-design-philosophy.md)** —
  the seven principles every new construct is judged against, and the
  standing method (sample real code) that keeps the design honest.
- **[`core-model.md`](core-model.md)** — the core in current vocabulary:
  value wires vs flow wires, uncollect/collect, (no) time travel
  (programs that leave ordering unstated are authorable, but are always
  completed to an explicitly-ordered form that shows what will actually
  happen), join, bundles, barriers-not-bottlenecks, and the table of
  flow kinds.

And once oriented, keep this one at hand — it spans everything below:

- **[`open-problems.md`](open-problems.md)** — the ranked index of open
  problems and incomplete areas, scored incompleteness × importance.
  Read its anti-tunnel-vision rules before treating it as a queue.

## The language description

- [`visual-language-spec.md`](visual-language-spec.md) — the
  data-representation spec: diagrams, nodes, ports, value vs flow wires,
  Delay.
- [`textual-representation-design.md`](textual-representation-design.md)
  — the parseable/printable textual form the other docs write examples
  in: sorted arrows (`->`, `~>`, `-~>`), postfix chains, ports and
  projections, taps, marks, lanes, and registers. If you want to *read
  the code samples* in the rest of the record, skim this first.

## Two fundamentals-in-waiting

Both of these are basic to the nature of the language rather than
individual constructs; they sit ahead of the construct docs because
they change how everything else is read.

- [`time-travel-programs-design.md`](time-travel-programs-design.md) —
  you may draw a program that leaves some of its ordering unstated (an
  under-committed, "time travel" program); the editor completes it by
  published rules and shows the completion faint. Basic to how programs
  are authored. *Exploration.*
- [`transformation-levels-design.md`](transformation-levels-design.md) —
  program and edit history as one structure; every lowering is a
  read-only derived view; nothing is ever mutated. Equally fundamental,
  but a reach goal — the nearer docs build toward it. *Exploration.*

## The biggest open area

- **[`iteration-with-state-design.md`](iteration-with-state-design.md)**
  — loop-carried state (running sums, accumulators, anything a loop
  updates as it goes). Two candidate surfaces are proven to compute the
  same results; the open question is which drawing is primary. The bar:
  easy for beginners *and* flexible enough for complex code. Start with
  the reader's guide at the top. Companion:
  [`iteration-rails-design-notes.md`](iteration-rails-design-notes.md)
  (the redesigned "rail" surface).
- **[`delay-ontology-design.md`](delay-ontology-design.md)** — the open
  problem split out of the doc above: what a Delay (the construct that
  carries a value to the next iteration) *is*, and which flow supplies
  its "next iteration" when more than one is in reach. Most of the
  original fork has dissolved; the hard residue is how several readers
  of one order-sensitive register over a multi-axis product each pick a
  reading order. The per-kind half — which flow kinds supply a "next
  iteration" at all — is worked as the owned-order criterion (a flow
  supplies one exactly when its firings carry a total order the flow's
  meaning owns, not one that merely happens at run time), cashing the
  register checks the incremental, concurrent-collect, async, and
  served rounds had written. *Exploration.*
- [`product-linearization-design.md`](product-linearization-design.md)
  — the doc above's one hard residue, worked: which order an
  order-sensitive register (or a spanning effect) walks a multi-axis
  grid in. The claim: no new construct — order-freedom at consumers is
  licensed by confluence and void where order is observed; the axis is
  the orientation Cross already stores, read as ordinary nesting; the
  one cost is an orientation-pinning demand (authored where observed,
  discharged by commutativity). If adopted, the collect-vs-ancestor
  fork closes. *Exploration.*

## Representation and checking

- [`first-class-ports-design.md`](first-class-ports-design.md) — a
  staged migration, first on the implementation path: every wire should
  name a *port* of a node, not a whole node. Making ports first-class
  dissolves the Branch node and the flowRef wrapper stack. Also: "the
  program is a node set" (not a root expression). Ports are meant to
  become a basic, assumed aspect of the language rather than a topic of
  their own — as the other docs come to assume them, this doc's content
  should be absorbed into theirs and the doc retired with the migration
  it stages.
- [`barrier-value-crossing-design.md`](barrier-value-crossing-design.md)
  — one place to answer how values cross barriers (joins, races, partial
  collects), a question several docs had deferred to each other. Two
  mechanisms plus a co-location rule. *Mixed: the mechanisms, the
  availability law, the co-location criterion, and flow-only joins
  adopted (2026-07-23, with the clarification that value wires are
  neither upstream nor downstream of a flow operation); the race
  corner adopted with the pairs-in amendment (race as the partial
  collect's async sibling); the partial-collect corner pending; the
  discharge corner contested by the discharge-barrier direction.*
- [`types-design.md`](types-design.md) — validity without a type system:
  properties that propagate along wires, witnesses you can draw, no
  search.
- [`bundle-provenance-design.md`](bundle-provenance-design.md) — the
  check that stops a program from combining values that can never
  coexist — a value from the Just branch of a case split with a value
  from the Nothing branch of the *same* split — while still letting
  branches of *different* splits nest freely. It works by tracking
  where each wire's value came from (its context path); the same
  tracking also catches time travel. *Exploration.*

## Editing

- [`program-editing-design.md`](program-editing-design.md) — how
  programs are edited (first vehicle: a curses-style TUI over the
  textual form): the cursor as a node/port/slot position plus a mark,
  every edit an atomic pure function preserving structural validity,
  and holes/planned wires as the representable partiality that makes
  that possible. Also the suggestion surface: the legal next edits at
  a position, enumerated as the checker of `types-design.md` run in
  reverse. Builds on the step-DAG and completion docs.
  *Exploration.*
- [`editor-state-management-design.md`](editor-state-management-design.md)
  — the doc above's state-architecture companion: the working record
  with the step-DAG head-first (current version cached at the head,
  all history levels behind it), the zipper question dissolved by the
  ports-first node set, and reuse of derived computations (checking,
  eligibility, completion) as history-shaped incrementality —
  memoization keyed by the step-DAG's identity discipline
  (constructive traces, no invalidation; undo and previews are cache
  hits), with the from-scratch recompute kept as the definition and
  the oracle. *Exploration.*

## Constructs

### Case splits and the collect family

- [`partial-collect-design.md`](partial-collect-design.md) — collecting
  only some branches of a case split; one k-ary partial-collect node.
- [`collect-family-design.md`](collect-family-design.md) — the empty
  collect (what does an empty sum/max return?), identities as catalog
  rows, and the keyed collect (group-by as flows). *Exploration.*

### Products of flows

- [`product-flows-design.md`](product-flows-design.md) — Cross, the node
  for combining two independent (sibling) flows without nesting one in
  the other; commute-as-transpose over products. Also its positional
  sibling, the aligned product (zip) — same-extent pairing by position —
  and the multi-wire collect (the table) as zip's value form.

### More flexible iteration

These loosen the basic loop's fixed shape — when it stops, how fast it
consumes, and whether it needs an input list at all:

- [`end-when-design.md`](end-when-design.md) — data-driven termination
  (stop the loop when the data says so): the surveys' biggest unserved
  everyday demand, worked as a binary flow operation. *Adopted
  (2026-07-23): the construct and the node-bit with exclusive default;
  spellings, the final-readout anchor, and the drawing still open —
  see the doc's adoption notes.*
- [`variable-rate-consumption-design.md`](variable-rate-consumption-design.md)
  — "advance how far?" reframed as placing segment boundaries
  (split-when), plus the running view of a collect. *Mixed: the cut
  root decided (2026-07-23 — end-when and split-when branch off one
  root, the cut; split-when is the iterated cut, not a separate
  primitive; see the status header); the running view reviewed and
  deliberately left tentative — the drawing, not the semantics, is
  the open problem.*
- [`source-openers-design.md`](source-openers-design.md) — flows with no
  input list (`repeat`, self-driven loops, external pull sources), plus
  pacing (gate the next firing on an async value). The most-witnessed
  unowned item in the surveys. *Exploration.*

### Recursive structures, search, and update

- [`trees-and-recursion.md`](trees-and-recursion.md) — iterating over
  trees and other recursive structures without writing a recursive
  function: a zipper-based uncollect walks the structure and exposes
  each node with its full context. *Exploration.*
- [`divide-flow-design.md`](divide-flow-design.md) — recursion whose
  tree exists only as call structure (mergesort's splits, a parser's
  descent, a quadtree build): write one level concretely, then *link*
  the sub-problems back to the problem — the register's link
  transformation, tree-shaped. Termination is a three-species measure
  discipline (structural shrink, cursor progress, drawn fuel); the
  left-recursion parser bug falls out as the progress measure's
  violation. *Exploration.*
- [`speculation-design.md`](speculation-design.md) — try-in-order choice
  with rollback: several alternatives drawn in order, each of which may
  fail; the first success wins, and the world is restored between
  attempts — the shape parsers and backtracking search need. It is
  race's *sequential* sibling, and restoration comes from the structure
  (every alternative reads the same input wire) rather than from a
  save/restore operation. *Exploration.*
- [`focused-update-design.md`](focused-update-design.md) — transform
  selected loci of a nested value, preserving the rest (increment every
  post's likes, redact one field): a structural selection read as a round
  trip, its write-back the derived mirror of the path (the lens); value-
  selected update is a case split with an identity branch, never a filter.
  *Exploration.*
- [`saturation-design.md`](saturation-design.md) — computing closure
  under rules (graph reachability, transitive closure, dataflow
  analysis): keep applying rules to a growing set until nothing new
  appears. Worked as a back-edge on a *flow* wire — a set collect
  re-opened — where the register is a back-edge on a *value* wire (a
  Delay). Naive vs semi-naive evaluation are lowerings of one drawing;
  the lattice variant is the keyed collect under feedback.
  *Exploration.*

### Effects and IO

- [`custom-flows.md`](custom-flows.md) — user-defined flow kinds, worked
  through the effect-handle lifecycle (open a resource, operate along
  its flow, close it) and which operations commute. The raw material
  the three docs below build on. *Exploration.*
- [`effects-design.md`](effects-design.md) — making a loop *do*
  something once per firing (print a line, write a row): the most
  common thing sampled loops are for. The piece to design is not the
  effect but its ordering — and the answer is one definition:
  commuting an IO flow out of a list flow *sequences* the
  operations, concatenating each firing's segment in firing order
  into one segment ("collect of an effect flow" is that
  concatenation's tail — one handle out, not a list). The commute is
  mandatory and unique because the handle is linear, so it is never
  drawn: consuming the handle after the loop does the job. An effect
  that needs no ordering gets its own per-firing-minted handle,
  which never crosses the loop boundary. Within-firing ordering and
  the batched (collected-plan) pole are fenced out. *Exploration.*
- [`within-firing-effects-design.md`](within-firing-effects-design.md) —
  effect ordering *within* one firing, and the conditional-flush buffer:
  within a firing there is no time — the only intra-firing order is
  along a handle's segment — and the buffer dissolves into a
  segmentation of the op flow (buffer = per-segment collect, reset =
  boundary, flush = per-segment write). Batching is meaning exactly when
  the sink's write doesn't coalesce (chunked encoding); a handle is an
  ordering commitment. *Exploration.*
- [`cancellation-design.md`](cancellation-design.md) — the other half of
  the IO row: cancellation and bracket. Stopping is drawn (race,
  interrupt, end-when); cancelling is *delivered* — the runtime writes a
  `Cancelled` terminator to in-flight work stranded by ceased demand,
  over the same necessity frontier the incremental flow uses, so there
  is no cancel token in the vocabulary. Bracket is the lifecycle segment
  plus a late-wired release half on the acquire (release on any end,
  keyed per terminator lane). *Exploration.*

## Reuse and abstraction

- [`functions-design.md`](functions-design.md) — functions as reusable
  sub-diagrams with ports, existing for naming, reuse, and modularity —
  deliberately *not* for map/filter bodies (flows do that) and *not*
  first-class values (a function waiting to be called has no honest
  visual form). *Exploration.*
- [`function-boundary-design.md`](function-boundary-design.md) — the
  boundary construct itself, the round three worked rounds jointly
  demanded: a function is a **remembered cut** through the wiring, not
  a container — ports are the wires the cut crosses (read off at
  extraction, never declared), membership is derived (per-call iff
  downstream of an in-port), closure capture dissolves into the prefix
  rule, and reusability is a derived check with a drawable witness.
  Functions per se are about *reuse* (sameness across sites — the
  honest form exactly where a manufactured shared flow would be a
  lie); the divide flow's link shares the cut's substrate while
  staying its own anonymous construct (recursion never routes through
  a named function — settled in the round's first design
  conversation), with the measure guarding reference cycles of any
  species. Partial cuts give local functions (uncut wires are free
  wires; the prefix rule derives the validity region; linear values
  force port-ification); the spec's slot dissolves into the op pair;
  function, level, provider, and the top-level program share one
  substrate under four bindings. *Exploration.*
- [`configuration-scopes.md`](configuration-scopes.md) — the replacement
  for higher-order arguments (comparators, predicates): instead of
  passing a function, open the operation as a scope and wire the
  would-be lambda body into it. *Exploration.*
- [`late-bound-operations-design.md`](late-bound-operations-design.md) —
  one program, many meanings: write a diagram against operations whose
  meaning is supplied per use, with the test double ("run it against
  fake IO") as the everyday face and middleware (logging, retry,
  fault injection) as the stacked form. An unbound operation is a
  request/response port pair on the boundary — the client end of a
  served flow; binding is wiring a provider on; unmet demands travel
  outward like the placeholder story's residue; the facet supplies
  the grouping identity. *Exploration.*
- [`facets-design-notes.md`](facets-design-notes.md) — early, deliberately
  undeveloped intuitions about *facets*: authorable, attachable
  abstractions (interfaces, algebras, state machines) you hang on code.
  Extends the facets material in `tough-use-cases-design.md`.

## Flow kinds beyond lists

The one open/collect shape is instantiated per kind. Lists and
case/option are implemented; the rest are designed:

- [`commute-design-notes.md`](commute-design-notes.md) — the
  commute-on-lists analysis (a superseded stopgap kept for its options
  survey) that led to streams.
- [`lazy-stream-join-design.md`](lazy-stream-join-design.md) — join as a
  binary flow operation (two flows in, one flow out). This is the
  correction the whole record now follows.
- [`lazy-stream-commute-design.md`](lazy-stream-commute-design.md) —
  commute across stream flows; the commute-variant taxonomy.
- [`async-flow-design.md`](async-flow-design.md) — the async flow:
  values that arrive later, racing as a barrier, failure as a terminator
  payload.
- [`failure-payloads-design.md`](failure-payloads-design.md) — the
  failability dimension's two flagged residues, worked: lightweight
  failure (`fail`, the raise as a drawn node — bodies never throw; the
  JS edge converts declared throws by catalog row) and payload
  composition (a flow's possible endings as a derived *inventory* of
  drawn minting sites — union by propagation, exhaustive discharge
  with witnesses, re-tagging drawn only where meaning changes). Cashes
  the payload checks the cancellation, race, speculation, divide-flow,
  and served-flow rounds had filed here. *Adopted (2026-07-23): the
  fail node (with the ontology note — fail is the minting half of
  the applicative sequence — and the commute-completion ruling), the
  edge stance with the background-super-flow amendment (undeclared
  throws quarantined in one runtime-owned collectable lane), and the
  inventory account. Tag identity across reuse boundaries is the
  residue owing a worked round.*
- [`race-barrier-design.md`](race-barrier-design.md) — the race
  barrier's own semantics: first-to-settle wins, ties by drawn order,
  merge/interrupt/timeout as derived vocabulary. *Exploration.*
- [`concurrent-collect-design.md`](concurrent-collect-design.md) —
  running async work for every firing of a walk and taking the results
  as they finish rather than in walk order (a server handling requests,
  a scraper fetching URLs). One primitive (settle) mints a *completions
  flow*: one firing per body that settles, in settlement order,
  failures carried as data. *Exploration.*
- [`served-flow-design.md`](served-flow-design.md) — the served flow:
  flows whose firings are *exchanges* — a request in, a response owed
  back, the collect supplying the answer. One construct with two ends:
  the client end is late-bound operations' `op` pair; the server end is
  a provider diagram, and "which one is the server" is a property of a
  binding (an HTTP server is a provider bound to the network; the same
  provider bound to a scripted requester is a test). Also the
  k-operation provider as a pre-split bundle, the recursive provider as
  the link in exchange costume, the keyed cache as a
  partition-plus-lane-register middleware, and the first joint working
  of the top-down/bottom-up duality with saturation. *Exploration.*
- [`incremental-flow-design.md`](incremental-flow-design.md) — the
  incremental flow (reactive vars): hold/changes, cutoff, and pushing
  values into a "necessity frontier."

## Compile

- [`lazy-compile-design.md`](lazy-compile-design.md) — the
  **implemented** runtime-lazy strategy in `src/Compile.res`.
- [`compile-strategy-design.md`](compile-strategy-design.md) — the
  planned rebuild: a pipeline of pure passes, same semantics.
- [`lazy-stream-placement-design.md`](lazy-stream-placement-design.md) —
  how stream (pull-based, on-demand) flows compile. The committed
  baseline is per-node memoised streams, with the compiler deciding
  nothing about placement — the implemented eager strategy transposed
  to streams; the consumer-set analysis that would merge one conceptual
  loop into one emitted loop is a deferred optimisation, not a
  rejection (see the doc's status header).
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

## Sequencing

- [`implementation-strategy.md`](implementation-strategy.md) — the map
  from the whole design record to code — not just the compiler: five
  workstreams (representation, compile pipeline, runtime, checking, text
  surface), what blocks what, and a proposed sequencing. The
  compiler-specific half of the map is `compile-strategy-design.md`.

## Layout (out of scope in this repo)

Kept because the layout algorithm should survive, but the graphical side
is out of scope for work here. Each carries a status header noting where
its vocabulary predates the newer rounds.

- [`graph-representation.md`](graph-representation.md)
- [`visual-layout-guidelines.md`](visual-layout-guidelines.md)
- [`rendering-algorithm.md`](rendering-algorithm.md)
- [`program-to-graph-transformation.md`](program-to-graph-transformation.md)
