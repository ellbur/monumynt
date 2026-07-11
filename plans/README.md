# Design documents

*Index, 2026-07-09. Reading order matters here: the record is layered
design conversations, and later docs correct earlier ones with dated
notes. Each doc's status header tells you where it stands; this index
tells you where to start.*

## Start here — the fundamentals

Everything else hinges on these two:

- **[`language-design-philosophy.md`](language-design-philosophy.md)**
  — the seven principles every new construct is evaluated against.
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
  — loop-carried state. The two live candidates (Delay in port form;
  the latent-flow augmented uncollect) are now proven **result-level
  equivalent** (2026-07-10 round, "The equivalence, worked": one
  register-pair construct under two drawings, the feedback collect
  pinned as the write half, the thread as a third drawing), so the
  open decision moved from semantics to *surface*: which drawings
  exist and which is primary. Still undecided. The bar: easy for
  beginners *and* flexible enough for complex code.
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
- [`facets-design-notes.md`](facets-design-notes.md) — recorded
  intuitions (2026-07-10, deliberately undeveloped): facets as
  authorable, attachable abstractions — the concrete/schematic
  gap, the struct → interface → facet ladder, algebras and state
  machines as code facets, holes without breaking, negative
  constraints, and the views-not-verification bound. Extends the
  facets addendum in `tough-use-cases-design.md` (which owns the
  viewing side) with the attachment side.

## Representation and checking

- [`first-class-ports-design.md`](first-class-ports-design.md) — the
  Expr-level port representation dissolving Branch and the wrapper
  stack; the Delay write half; the program as a node set. Staged
  migration; first on the implementation path.
- [`barrier-value-crossing-design.md`](barrier-value-crossing-design.md)
  — the one-place answer to how values cross barriers, the question
  four docs deferred to each other: two mechanisms (availability by
  provenance; minted ports) plus a co-location criterion. The four
  corners each answered: Join and the concurrent join stay
  flow-only; race keeps its per-contender (value, flow) pairs,
  values-in; no multi-row partial collect — m rows are m sibling
  collects at one context; the discharge is one settled-sum port on
  exactly-one kinds, the (prefix, terminator) pair on many kinds.
  **An exploration round with leanings, not an adopted design** —
  prepared for the design conversation; five dead ends recorded.
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
- [`end-when-design.md`](end-when-design.md) — data-driven
  termination, the surveys' biggest unserved everyday demand, worked
  as a binary flow operation (subject, stop) with the readout via
  terminator discharge. **An exploration round with leanings, not an
  adopted design** — prepared for the design conversation. Its open
  question 5 (stacked end-whens vs the merged stop) is worked at the
  end of the doc: agreement exactly where the merged form is
  well-formed (one bundle — a level-1 recognition rule), meaningful
  stacking order beyond it.
- [`variable-rate-consumption-design.md`](variable-rate-consumption-design.md)
  — the breadth set's ownerless cluster worked: "advance how far"
  reframed as boundary placement (split-when, a segmenting binary
  flow operation) and the running view of a collect answered as the
  state port of the collect's derived augment form. **An exploration
  round with leanings, not an adopted design** — prepared for the
  design conversation; three dead ends recorded.
- [`source-openers-design.md`](source-openers-design.md) — the
  record's most-witnessed unowned item worked (2026-07-11): the
  self-driven flow's opener (a bare flow-minting node — the node the
  iteration-state equivalence round said the port form must borrow),
  its kind answered as the sourceless stream (no new kind), counted
  repetition split off as range data, **pacing** worked as a binary
  flow operation (`paced` — sibling of end-when and interrupt,
  gating the next firing on a per-firing async value's settlement),
  and the external pull source as a catalog block minting a failable
  stream, its block boundary a deliberate fence around the Tier-1
  effect hole. The corecursion boundary stated (repetition as
  meaning vs corecursion as encoding). **An exploration round with
  leanings, not an adopted design** — prepared for the design
  conversation; four dead ends recorded.
- [`collect-family-design.md`](collect-family-design.md) — the
  joint spelling-and-identity round three docs requested
  (2026-07-11): the operator-identity question reframed as the
  **empty-collect question**, answered with a three-tier
  availability ladder (monoid → total; associative-without-identity
  → option-shaped; neither → augment) and identities as **catalog
  rows carrying the identity value as witness** (user monoids
  minted via the algebra facet, trusted like the JS edge); the
  named collects (set/any/last/…) dissolved into catalog rows on
  the one reduce-close node; and the **keyed collect** worked as a
  keyed partition (group-as-flows primary, uniform wiring over
  data-determined lanes) with the four readouts
  (collapse/pass-through/flatMap/whole-lane) as consumption,
  operator-merge as the fused special case, first-appearance
  order, `from`-seeding for initial contents, and the
  lanes-are-non-empty observation making semigroup operators total
  in keyed position. **An exploration round with leanings, not an
  adopted design** — prepared for the design conversation; eight
  dead ends recorded.

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
- [`race-barrier-design.md`](race-barrier-design.md) — the race
  barrier's own semantics round (the piece survey 3 put first):
  the barrier's law with drawn-order ties, the unary race as the
  async uncollect, subset merges failable by construction,
  dynamic sets redirected to the completions stream, the
  lost-cell cancellation hook, merge/interrupt/timeout as
  derived vocabulary. **An exploration round with leanings, not
  an adopted design** — prepared for the design conversation;
  five dead ends recorded.
- [`concurrent-collect-design.md`](concurrent-collect-design.md)
  — the concurrent collect's own round (2026-07-11), which
  dissolves the name along with the species menu: `serial` is
  the ordinary nested drawing, `keyed` is the keyed partition
  instantiated (lane-serial by nesting, cross-lane overlap by
  siblinghood — the replug race dissolves), and what remains is
  one primitive binary flow operation (**settle**, placeholder
  name) minting the **completions flow** — one firing per body
  settlement, in settlement order, the input firing's values
  crossing by availability and the settled result minted as a
  per-firing discharged sum (failures as data for supervisors).
  The drain termination law makes graceful shutdown a +1 ladder;
  output ordering dissolves (no main-result port; completion
  order is a downstream collect, input order a commute-family
  reassembly); registers are ill-formed across bodies and
  ordinary on the completions flow; `bounded(n)` splits into a
  width (configuration, now) and shared permits (bracket-shaped,
  failable, Tier-1); exhaustMap files to the source-boundary
  family (buffer/latest/drop), not to a collect species. **An
  exploration round with leanings, not an adopted design** —
  prepared for the design conversation; six dead ends recorded.
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
- [`real-loop-survey.md`](real-loop-survey.md) — the sampling
  record, three seeded-random runs (evidence, not design). Runs 1–2:
  sixty loops (infrastructure corpora, then numerics/algorithms/
  simulation/UI/games/graphics) classified against the inventory:
  uncollect/collect confirmed as the center; the scan absent in
  infrastructure but dominant in numerics, with cross-referencing
  registers in the wild; early exit the biggest unserved everyday
  demand; the thread's one-writeback rule unbroken across all sixty;
  Cross, window, and the event-loop inventory sighted in their
  designed shapes. Run 3 (2026-07-10): thirty concurrency
  *orchestration sites* from server/async-heavy corpora, giving
  inventory items 1–3 the frequency treatment — first-of
  coordination (race/timeout/interrupt/cancellation) outweighs
  all-of nine-to-one, with the discrimination always reconstructed
  from side flags; the deferred cell is the most-reached-for
  primitive; `bounded(n)`-as-resource confirmed; cancellation
  measured at roughly a quarter of sites. Read the tallies with the
  80/20 counterweight (frequency ranks the effortless; the rare
  painful tail binds breadth — the nine-loop **breadth set** is
  collected at the end of run 2). Runs of a **standing method** —
  sampling reality is to be used frequently; the method's statement
  and rules are in `language-design-philosophy.md`, "A standing
  method: sample reality."
- [`translation-exercise.md`](translation-exercise.md) — the
  surveys' sampled loops transcribed into the textual form
  (2026-07-10): thirteen translations from trivial to breadth-set,
  every invented spelling marked provisional and gathered in one
  table. The core and the scans carried cleanly; the ranked
  improvement list at the end is the round's output — per-firing
  effects unwritable (the Tier-1 row's everyday failure mode),
  bodies-raise and source openers missing, the write-half
  two-phase form demanded by every on-cycle operand, the collect
  family's spelling-and-identity debt.
- [`effekt-comparison.md`](effekt-comparison.md) — first
  learning-from-other-languages round (2026-07-10): Effekt's nine
  case studies and tour read against the record — problems
  extracted, never mechanisms; reading rules for the genre
  (curated-corpus bias — this is *not* a random sample) stated in
  the doc. Yield: one new open problem (speculation — ordered
  alternatives with rollback), two demands for the functions row
  (late-bound operations; the test double), two for the served
  flow (recursive provider; keyed cache), a clash record of what
  must not be imported and why, and confirmations for the IO,
  end-when, and source-opener items.
- [`raku-grammars-comparison.md`](raku-grammars-comparison.md) —
  second learning-from-other-languages round (2026-07-10): Raku's
  grammar and regex documentation read against the record — a
  documentation corpus, so structure only, no field sightings
  (reading rule 4 there). Organizing observation: grammars as a
  special case of *inhomogeneous iteration*, an algebra for buying
  complex loops by adding atoms, none of it text-specific. Yield:
  the grammar ladder's unowned phase-sequence rung and the
  deterministic/trial fork (to the variable-rate row), structure
  for the speculation row (two choice constructs, commitment,
  error diagnosis in scope), parsing as the divide flow's everyday
  client, extensible alternation (to the functions row), a
  split-when confirmation sweep, and a clash record (sigspace,
  dynamic variables, method-name action binding, declarator-chosen
  rollback).
- [`flix-comparison.md`](flix-comparison.md) — third
  learning-from-other-languages round (2026-07-10): the Flix
  example suite (~190 programs — first-class Datalog, the
  effect-handler stdlib ecosystem, channels, regions, restrictable
  variants) read against the record. Yield: one new open problem
  (saturation — closure under rules, with keyed-merge and
  provenance-explanation in scope), the policy layer (middleware)
  and the decorated tree handed to the functions row alongside the
  test double's third witness, the purity mirror's two demands,
  piecewise concurrency confirmations (poll arm, scope-bound
  spawn, source opener, pacing), restrictable variants as prior
  art for recursive shape checking, and a clash record (dynamic
  handler reach, continuations as data, unification by name
  coincidence, type algebra as the safety story).
- [`xquery-jq-comparison.md`](xquery-jq-comparison.md) — fourth
  learning-from-other-languages round (2026-07-10), the dataflow
  round: the family's two shipped relatives — XQuery's
  FLWOR/windowing/grouping machinery, use cases, and Update
  Facility; jq's manual and community cookbook — read against the
  record, with the reading-rule flip for close relatives stated
  (the risk is mistaking familiarity for validation; read hardest
  where they strain). Yield: one new open problem (focused update
  — transform selected loci of a nested value, preserving the
  rest), the effects row's first structural prior art (the
  pending update list — effects as collected values applied at a
  snapshot barrier), the window clause as split-when's
  confirmation sweep with three new pieces (neighborhood bindings
  vs the destination knob, the unterminated-final-segment bit,
  gap-tolerant segmentation), the keyed collect's group-as-flows
  primary form, the shipped running view (`foreach`), a fifth
  source-opener witness, and a clash record led by the
  anti-lesson: implicit flattening and the single-context-value
  bottleneck are the two costs the record's explicit-join,
  multi-wire core exists to avoid.
- [`apl-family-comparison.md`](apl-family-comparison.md) — fifth
  learning-from-other-languages round (2026-07-10), the array
  round, run under a stated brief: the higher-order operator
  layer is not wanted (the uncollect's virtual value does the
  work of every operand slot); the round reads the family's
  programs — FinnAPL's 707 idioms, Dyalog reference and
  notebooks, BQN's argued docs, BQNcrate — hunting for ones the
  drawn vocabulary struggles to represent. Yield: the
  operator-catalog audit (the family's second-order layer maps
  item-for-item onto the record's first-order constructs), the
  aligned product (zip) promoted to a demand as the one localized
  struggle, the focused-update row's structure round (structural
  Under's commuting law, the loci-as-data condition, derived-view
  updates, the Expand dissolution), window(k)'s shipped design
  space, the identity catalog with the empty-collect framing, and
  a clash record (tacit composition, inverse inference, shape
  coincidence, the ambient index origin, idiom-recognition
  compilation).
- [`reactive-comparison.md`](reactive-comparison.md) — sixth
  learning-from-other-languages round (2026-07-10), the reactive
  round, run under a stated brief: the universe is Elm plus the
  JS state libraries, the monad-like reactive-variable core is
  already the incremental flow (verified — the TC39 Signals
  proposal matches `incremental-flow-design.md` point for point,
  and Elm removed signals entirely), and seven boundary questions
  are the schedule: partial updates, async inputs, vars × events,
  output to the DOM, liveness, inhomogeneous/protocol events,
  keyed fan-out. Yield: the necessity frontier confirmed as the
  genre's shipped shape (watched/unwatched hooks as the derived
  registration events; dirty/check/clean as the intermediate
  algorithm), the collections layer's shipped shapes (keyed var
  families, per-key subscriptions, prefix invalidation, deltas as
  data, the identity-vs-position fork), the Tier-1 effects hole
  acknowledged at standards level with Elm's `Cmd` as the second
  effects-as-data witness, the flattening strategies as the
  shipped concurrency menu (exhaustMap a new species), the
  statechart category as custom-protocol-flows' second demand,
  The Elm Architecture drawn in six existing constructs, and a
  clash record led by auto-tracking (the invisible wire at
  ecosystem scale, with its documented footgun bill).
- [`zig-comparison.md`](zig-comparison.md) — seventh
  learning-from-other-languages round (2026-07-10), the imperative
  round, run under a stated brief: Zig deliberately redesigned C's
  control flow, so each modification is read as a field-tested
  claim about where raw imperative control flow fails, checked
  against the record. Central confirmation: the redesigned loop
  headers decompose into exactly the record's constructs (the
  `while` header is end-when plus the register write half;
  `break v`/`else d` is the discharge readout shipped as
  syntax). Yield: the bracket half's structural prior art
  (defer/errdefer — adjacency, exit-reason keying, the
  infallibility asymmetry, per-firing attachment; cancel-as-await
  from the new `std.Io`), field answers for failability's two
  flagged residues (try; error-set algebra), the source-opener
  priority correction (the imperative ground-floor loop starts
  off the page), zip's second shipped witness (multi-object
  `for`), the custom-protocol-flows probation's first field
  sighting (labeled switch in the production tokenizer), the
  late-bound-operations witness with fault injection
  (FailingAllocator), and a clash record led by
  visibility-by-prohibition vs by-drawing.
- [`tidyverse-comparison.md`](tidyverse-comparison.md) — eighth
  learning-from-other-languages round (2026-07-10), the tabular
  round: dplyr/tidyr/purrr vignettes read against the record,
  under the stated question "is a table more than a list of
  structs?" Answer: yes — the data frame is the multi-wire flow
  at rest (k columns = wires, n rows = firings, alignment
  retained from common provenance), the third shipped member of
  the tuple-stream family. Yield: the aligned product's **value
  form** (the multi-wire collect/uncollect — products row, W
  raised), the keyed partition's **readout family**
  (collapse/pass-through/flatMap — grouped summarise vs mutate),
  the broadcast-back as a fold-then-re-walk composite, the
  pivots dissolved into the keyed pair once static-schema and
  data-keyed columns are distinguished, the purrr audit
  (`done()` as end-when-as-a-value; `modify` as focused update's
  sixth witness), and a clash record led by ambient magic names
  and grouping as a mode bit. Deliberately no new row.
- [`implementation-strategy.md`](implementation-strategy.md) — the
  map from the design record to code: workstreams, ledger,
  sequencing.
- [`open-problems.md`](open-problems.md) — the ranked index of open
  problems and incomplete areas: broad pointers into the other
  docs, scored incompleteness × importance and re-assessed whenever
  an area is worked. Read its anti-tunnel-vision rules before
  treating it as a queue.

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
