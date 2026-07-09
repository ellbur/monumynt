# Design documents

*Index, 2026-07-09. Reading order matters here: the record is layered
design conversations, and later docs correct earlier ones with dated
notes. Each doc's status header tells you where it stands; this index
tells you where to start.*

## Start here — the fundamentals

Everything else hinges on these two:

- **[`language-design-philosophy.md`](language-design-philosophy.md)**
  — the six principles every new construct is evaluated against.
- **[`core-model.md`](core-model.md)** — the core in current
  vocabulary: value vs flow wires, uncollect/collect, no time travel,
  binary join, bundles, barriers-not-bottlenecks, the flow kinds.

Rejected and dissolved ideas are recorded **in place**, in the doc
that owns the topic — short, and focused on the reason the idea must
not be pursued again. Four statuses are commonly misread, so, stated
once here: the compile-time placement pass and the stream
consumer-set lattice are *deferred* optimisation passes, not
rejections; the two iteration-state candidates are *both live*;
Incorporate is a live primitive (only its sibling-opens use was
corrected to Cross); pure pull for incremental flows is a
first-implementation convenience, rejected long-term.

## The biggest open area

- **[`iteration-with-state-design.md`](iteration-with-state-design.md)**
  — loop-carried state. Two live candidates deliberately side by side
  (Delay in port form; the latent-flow augmented uncollect), plus a
  conjectured fourth option (the visible state thread). Undecided.
  The bar: easy for beginners *and* flexible enough for complex code.
  The reader's guide at the top gives the current state.
  Companions: [`iteration-rails-design-notes.md`](iteration-rails-design-notes.md)
  (the redesigned rail; rail ideas deliberately kept) and the Delay
  back-edge sections of `first-class-ports-design.md`.

## The language description

- [`visual-language-spec.md`](visual-language-spec.md) — the
  data-representation spec: diagrams, nodes, ports, value vs flow
  wires, Delay.
- [`textual-representation-design.md`](textual-representation-design.md)
  — the parseable/printable textual form: three sorted arrows,
  postfix chains, graded references, `+` completion lines.
- Topic docs distilled from the retired first-generation narratives
  (design-only): [`trees-and-recursion.md`](trees-and-recursion.md),
  [`functions-design.md`](functions-design.md),
  [`custom-flows.md`](custom-flows.md),
  [`configuration-scopes.md`](configuration-scopes.md).

## Representation and checking

- [`first-class-ports-design.md`](first-class-ports-design.md) — the
  Expr-level port representation dissolving Branch and the wrapper
  stack; the Delay write half; the program as a node set. Staged
  migration; first on the implementation path.
- [`types-design.md`](types-design.md) — validity without a type
  system: property propagation, drawable witnesses, no search.
- [`bundle-provenance-design.md`](bundle-provenance-design.md) —
  context paths; one check, two clash flavors (bundle mixing, time
  travel).

## Constructs

- [`partial-collect-design.md`](partial-collect-design.md) — partial
  conditionals settled: one k-ary partial collect; the old semantics
  menu dissolved into distinct programs.
- [`product-flows-design.md`](product-flows-design.md) — the Cross
  node for mutually-constant sibling flows; commute-as-transpose made
  lawful over products; revises the sibling-opens completion.
- [`time-travel-programs-design.md`](time-travel-programs-design.md)
  — under-committed authoring sanctioned: completion by published
  rules, shown faint, compiled by translation only.
- [`transformation-levels-design.md`](transformation-levels-design.md)
  — program and edit history as one structure; conversions as level-1
  computations; nothing mutates.

## Flow kinds beyond lists

- [`commute-design-notes.md`](commute-design-notes.md) — the
  commute-on-lists round (superseded stopgap; options analysis is the
  record) that led to streams.
- [`lazy-stream-placement-design.md`](lazy-stream-placement-design.md)
  — stream flows; **read the status header first** (Shape C is the
  baseline; the lattice is the deferred optimisation pass).
- [`lazy-stream-join-design.md`](lazy-stream-join-design.md) — join
  as a binary flow operation (the correction the whole record now
  follows); the J/F dissolution.
- [`lazy-stream-commute-design.md`](lazy-stream-commute-design.md) —
  commute as per-collect output construction; the commute-variant
  taxonomy.
- [`async-flow-design.md`](async-flow-design.md) — the async flow:
  event-loop values, racing as a barrier, failability as terminator
  payloads.
- [`incremental-flow-design.md`](incremental-flow-design.md) — the
  incremental flow (vars): hold/changes, cutoff, push-with-values
  inside a necessity frontier as the destination.

## Compile

- [`lazy-compile-design.md`](lazy-compile-design.md) — the
  **implemented** runtime-lazy strategy in `src/Compile.res`.
- [`compile-strategy-design.md`](compile-strategy-design.md) — the
  planned rebuild: a pipeline of pure passes, same semantics.
- [`placement-algorithm-notes.md`](placement-algorithm-notes.md) —
  the retired compile-time placement algorithm; its hybrid revival is
  deferred, not rejected.

## Stress tests and sequencing

- [`tough-use-cases-design.md`](tough-use-cases-design.md) — five
  real-system programs worked against the blocks until they break;
  the ranked candidate-block inventory.
- [`real-loop-survey.md`](real-loop-survey.md) — thirty seeded-random
  loops from real codebases classified against the inventory
  (evidence, not design): uncollect/collect confirmed as the center,
  the scan absent, early exit dominant, the thread's one-writeback
  rule survived its stated test. First run of a **standing method** —
  sampling reality is to be used frequently; the method's statement
  and rules are in `language-design-philosophy.md`, "A standing
  method: sample reality."
- [`implementation-strategy.md`](implementation-strategy.md) — the
  map from the design record to code: workstreams, ledger,
  sequencing.

## Layout (out of scope in this repo)

Kept because the layout algorithm should survive; each carries a
status header noting where its vocabulary predates the newer rounds.

- [`graph-representation.md`](graph-representation.md)
- [`visual-layout-guidelines.md`](visual-layout-guidelines.md)
- [`rendering-algorithm.md`](rendering-algorithm.md)
- [`program-to-graph-transformation.md`](program-to-graph-transformation.md)

## Retired documents

`flow_language_design.md` and `visual-flow-language.md` — the
first-generation narratives copied in from an older project — were
retired 2026-07-09. Their live content is in `core-model.md` and the
topic docs above; their superseded content is recorded, briefly, in
the docs that superseded it; the full originals are in git history.
Citations to them in older docs refer to that preserved record.
