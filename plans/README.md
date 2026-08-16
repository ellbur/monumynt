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
  the seven principles every new construct is judged against, the
  standing method (sample real code) that keeps the design honest,
  the ontology lens, and the visual-leap constraint (thinking about
  visual representations is in scope even though building them is
  not).
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
- [`language-cheat-sheet.md`](language-cheat-sheet.md) — every
  construct on one page, each with a minimal example, in the most
  up-to-date desired design (newer revisions win over older
  spellings). A derived quick-reference, not part of the record — it
  decides nothing, and each construct's own doc is authoritative;
  status tags say what is implemented, adopted, or exploration.

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
  same results, and *the surface decision is made* (2026-07-23): the
  visible state thread is the primary framing — the register pair
  stored, the Delay point and the augmented flow its projections. The
  ergonomics round is now opened (2026-08-04), first pieces settled:
  the thread as a third connector species (`@`, provisional), no flow
  operand on the register — the frame *derived* from the anchors'
  contexts with an `in ~flow` annotation for the residue (nesting,
  self-driven loops), anchors as ports (read port: write-at-n−1 else
  init), and the exit as a scoop of the read port at whichever closer
  the author wires. The generic-iteration picture constraint and
  the constant-space caution are recorded in the doc's adoption note.
  Start with the reader's guide at the top. Companion:
  [`iteration-rails-design-notes.md`](iteration-rails-design-notes.md)
  (the redesigned "rail" surface, promoted to input for that round).
- **[`delay-ontology-design.md`](delay-ontology-design.md)** — the open
  problem split out of the doc above: what a Delay (the construct that
  carries a value to the next iteration) *is*, and which flow supplies
  its "next iteration" when more than one is in reach. Most of the
  original fork has dissolved; the hard residue is how several readers
  of one order-sensitive register over a multi-axis product each pick a
  reading order. The per-kind half — which flow kinds supply a "next
  iteration" at all — is **adopted** (2026-07-23) as the owned-order
  criterion (a flow
  supplies one exactly when its firings carry a total order the flow's
  meaning owns, not one that merely happens at run time), with the
  order-demand check and the `hold` identification, cashing the
  register checks the incremental, concurrent-collect, async, and
  served rounds had written. *The rest exploration — the linearization
  residue's evidence is delivered (survey 4) and the value-in-context
  model's everyday-`prev` check too (survey 5); both conversations
  remain unheld. A 2026-08-12 working round rides in the doc ("The
  frame menu"): the owned-order table read as offers — a thread
  names a frame kind, resolved from its anchors' provenance, with
  pins mandatory where ambiguous; exploration.*
- [`product-linearization-design.md`](product-linearization-design.md)
  — the doc above's one hard residue, worked: which order an
  order-sensitive register (or a spanning effect) walks a multi-axis
  grid in. The claim: no new construct — order-freedom at consumers is
  licensed by confluence and void where order is observed; the axis is
  the orientation Cross already stores, read as ordinary nesting; the
  one cost is an orientation-pinning demand (authored where observed,
  discharged by commutativity). If adopted, the collect-vs-ancestor
  fork closes. The frequency check it owed is run
  (`real-loop-survey.md`, survey 4) — evidence in, conversation not
  yet held. *Exploration.*

## Representation and checking

- *(The first-class-ports doc was retired 2026-08-12, per its own
  plan: the migration it staged is complete — ports and the node
  set are basic, assumed aspects now — and its surviving content
  lives in `core-model.md` ("Where to go next", ports entry) and
  `src/ARCHITECTURE.md`'s decision record.)*
- [`barrier-value-crossing-design.md`](barrier-value-crossing-design.md)
  — one place to answer how values cross barriers (joins, races, partial
  collects), a question several docs had deferred to each other. Two
  mechanisms plus a co-location rule. *Mixed: the mechanisms, the
  availability law, the co-location criterion, and flow-only joins
  adopted (2026-07-23, with the clarification that value wires are
  neither upstream nor downstream of a flow operation); the race
  corner adopted with the pairs-in amendment (race as the partial
  collect's async sibling); the partial-collect corner adopted (m
  siblings, with a naming constraint — not a "collect"); the
  discharge corner resolved by the one-closer principle — the
  discharging collect mints outcome cells directly, no packed
  terminator value. All corners decided. Extended (2026-08-04): the
  minted-selection extraction named the scoop, generalized to the
  short-circuit commute; inferred scoops (routing, never selection)
  upgrade the flow-borne witness to a three-way classification; the
  tunnel (stow/unstow) as the sanctioned packed transport,
  exploration. Reopened in part (2026-08-15/16): the case-cell account
  re-founds the short-circuit commute as the compact projection of a
  case-cell scope lift and re-states the scoop as routing of the
  selected `(error, %Error)` witness — see
  `case-commute-polarity-design.md`; nothing adopted.*
- [`types-design.md`](types-design.md) — validity without a type system:
  properties that propagate along wires, witnesses you can draw, no
  search.
- [`catalog-schema-design.md`](catalog-schema-design.md) — the doc
  above's question 4, worked: the catalog (the registry every round
  kept filing rows into) as **one registry of referent-identified
  entries** — entry/block/row as three grains of one thing — with
  facts in open-ended families (ports, laws, lanes, translations,
  measures, expansions), each family earned by a filed client;
  trust graded per fact (definitional vs asserted, every asserted
  fact carrying a stated direction of doubt); an admission rule
  (use-independent facts only — per-use truth is drawn, never
  registered); the lawful empty entry for unregistered JS; and the
  trust manifest — what *this program* trusts — as a derived view.
  *Exploration.*
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
  rows, and the keyed collect (group-by as flows). *Mixed: the
  availability ladder adopted (2026-07-23 — monoid total, semigroup
  option-shaped, non-associative augment-only; the runtime-error and
  fake-∞ poles confirmed rejected); spellings and the keyed collect
  still exploration.*

### Products of flows

- [`product-flows-design.md`](product-flows-design.md) — Cross, the node
  for combining two independent (sibling) flows without nesting one in
  the other; commute-as-transpose over products. Also its positional
  sibling, the aligned product (zip) — same-extent pairing by position —
  and the multi-wire collect (the table) as zip's value form. Join on
  a product is now worked in place (question 4): the operand-walk
  rules over the poset, the join chain as an orientation-authoring
  surface, witness-neutral. *Exploration.*

### More flexible iteration

These loosen the basic loop's fixed shape — when it stops, how fast it
consumes, and whether it needs an input list at all:

- [`end-when-design.md`](end-when-design.md) — data-driven termination
  (stop the loop when the data says so): the surveys' biggest unserved
  everyday demand, worked as a binary flow operation. *Adopted
  (2026-07-23): the construct and the node-bit with exclusive default.
  Revised (2026-08-04): fused with its collect into collect-until —
  no first-class shortened-flow wire; payloads travel value wires;
  terminators carry only the reason a flow ended. Spellings and the
  drawing still open — see the doc's adoption and revision notes.*
- [`variable-rate-consumption-design.md`](variable-rate-consumption-design.md)
  — "advance how far?" reframed as placing segment boundaries
  (split-when), plus the running view of a collect. *Mixed: the cut
  root decided (2026-07-23 — end-when and split-when branch off one
  root, the cut; split-when is the iterated cut, not a separate
  primitive; see the status header); the cut round itself now
  worked (Part III, exploration, unadopted): the two-flow-output
  port shape, the empty continuation on RanOut, payload from the
  continuation side, the node's totality-by-construction with the
  spine-shaped link as its derived view, and the finite phase
  chain claiming Raku's* sequence *combinator; the running view
  reviewed and deliberately left tentative — the drawing, not the
  semantics, is the open problem. Revised (2026-08-04): the boundary
  payload re-homed from the segment terminator to a value output on
  the outer flow; the fused-collect rejection re-grounded — the
  iterated cut mints the outer flow, the home of once-per-segment
  values, which is why it stays a flow operation while end-when
  fused into collect-until.*
- [`source-openers-design.md`](source-openers-design.md) — flows with no
  input list (`repeat`, self-driven loops, external pull sources), plus
  pacing (gate the next firing on an async value). The most-witnessed
  unowned item in the surveys. *Exploration.*
- [`chooser-family-design.md`](chooser-family-design.md) — the round the
  record kept citing as "the chooser family's": the decision-driven
  merge (mergesort's merge, the last unworked member of the
  decision-driven family), merge fairness, and cross-client
  arbitration, worked as one construct. The result: the chooser is not
  a construct — one node (a walk over k cursors) exposes per-step heads
  and takes a late-wired advance operand, and every "chooser" is
  ordinary drawn vocabulary (a case split, a race, a register read)
  wired between those ports; stop is end-when itself on the step flow,
  and heuristic-order speculation dissolves into existing vocabulary.
  *Exploration.*

### Recursive structures, search, and update

- [`trees-and-recursion.md`](trees-and-recursion.md) — iterating over
  trees and other recursive structures without writing a recursive
  function: a zipper-based uncollect walks the structure and exposes
  each node with its full context. *Exploration, with the soundness
  seam decided (2026-07-23): the verifier retires, computed-value
  zipper ports re-read as drawn crossings, the compact form a
  derived view.*
- [`divide-flow-design.md`](divide-flow-design.md) — recursion whose
  tree exists only as call structure (mergesort's splits, a parser's
  descent, a quadtree build): write one level concretely, then *link*
  the sub-problems back to the problem — the register's link
  transformation, tree-shaped. *Adopted (2026-07-23, in the joint
  adoption, under the anchor-is-identity constraint). Revised
  (2026-08-12, the doc's revision notes): the link's spelling lands
  as the **site** — an out-port/in-port pair joined by the abstract
  wire, threads anchored at the page's own fed and read wires (feed
  the child where you are fed, read it where you are read) — with
  the **hypothetical** ("what would y be if x were v?") as the
  primary ontology and a substitution law for nested frames; mutual
  recursion re-founded by inlining (only a group's back edges are
  sites; level labels dissolve; the reuse residue is two remembered
  cuts over one node set); the termination/measure discipline
  **retired** (no termination or soundness checking); the cyclic
  back-edge surface worked and **rejected** (clockless latch,
  crossing observability, branching collision). The frame-source
  question is answered by dissolution (frames are hypothetical
  assignments indexed by the tree of askings), and a follow-on
  exploration rides in the doc: the **frame flow** — the call
  tree as a tappable flow (thread-named, rooted at the current
  frame, firings = askings, unowned order), making whole-tree
  aggregation an ordinary collect; unadopted. Still open: final
  spellings; the wound (tree-structured) form.*
- [`speculation-design.md`](speculation-design.md) — try-in-order choice
  with rollback: several alternatives drawn in order, each of which may
  fail; the first success wins, and the world is restored between
  attempts — the shape parsers and backtracking search need. It is
  race's *sequential* sibling, and restoration comes from the structure
  (every alternative reads the same input wire) rather than from a
  save/restore operation. *Exploration; failability substrate
  re-founded 2026-08-14 onto the revised failure account (contender
  forks as case alts, per-contender pairs, diagnoses by wire).*
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
  the batched (collected-plan) pole are fenced out. *Exploration,
  with a recorded direction (2026-07-23): IO is a flow, not a
  handle — ops as uncollects joining into one global IO flow,
  join's asymmetry the sequencing, the handle derived; granularity
  dissolves into a fork/join readability program; external-world
  interaction filed as a facet. See the doc's IO-as-flow section.*
- [`subordinate-flows-design.md`](subordinate-flows-design.md) — what
  carries a flow's firings into a broader sequence, and what keeps
  them out — worked through the smallest conditional-effect program
  (if the line is "abc", print "yes"; otherwise nothing). The case
  boundary gets its crossing: a **case collect selecting flow wires**
  (the firing cell's continuation, the collect's verbatim law
  extended to a new wire sort), while the list boundary keeps the
  never-drawn sequencing commute; `in` is the incorporate, inferable
  when unambiguous; the first program pushed through the IO-as-flow
  desugar, dissolving two handle-spelling artifacts (mandatory
  coverage on flow lanes, sibling linearity). Ends with the
  membership table this agenda grows from. *Exploration
  (2026-08-16).*
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
  visual form). *Superseded-and-adopted: the boundary round
  (`function-boundary-design.md`) carries this chapter's stances and
  is adopted (2026-07-23).*
- [`function-boundary-design.md`](function-boundary-design.md) — the
  boundary construct itself, the round three worked rounds jointly
  demanded: a function is a **remembered cut** through the wiring, not
  a container — ports are the wires the cut crosses (read off at
  extraction, never declared), membership is derived (per-call iff
  downstream of an in-port), closure capture dissolves into the prefix
  rule, and reusability is a derived check with a drawable witness.
  Functions per se are about *reuse* (sameness across sites — the
  honest form exactly where a manufactured shared flow would be a
  lie); the divide flow's link stays its own anonymous construct
  (recursion never routes through a named function — settled in the
  round's first design conversation). Partial cuts give local
  functions (uncut wires are free wires; the prefix rule derives
  the validity region; linear values force port-ification); the
  spec's slot dissolves into the op pair; function, provider, and
  the top-level program share one substrate under three bindings
  (the level binding removed 2026-08-12 — recursion rides the
  port-pair substrate, not the cut; level labels and the measure
  references retired with it; see the divide flow's revision
  notes). Extended (2026-08-04): the cut
  re-founded as a node set with per-wire cut-or-environment
  decisions (the closed curve was topologically incoherent);
  copy-paste instance semantics, no context memory; flow ports as
  the drawn call-by-name (flow-level case selection filed as owed);
  containment derivable; per-instance checking, isolation checking
  sound but partial. *Adopted (2026-07-23, the joint
  adoption with the divide flow and late-bound operations), under
  the anchor-is-identity constraint and with a
  provisional-confidence marker on the slot-dissolution piece; edit
  gestures, spellings, and version identity remain with their
  rounds.*
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
  the grouping identity. *Adopted (2026-07-23, in the joint
  adoption). Revised (2026-08-04): the op construct dissolves into
  an ordinary out-port/in-port pair — `with`-binding rejected,
  exchange pairing derived under copy-paste, the flow-use marking
  the one stated exception (resolving the slot marker); the
  abstract-wire annotation and the C-shape land, and a custom flow
  is a C-shaped sub-diagram used flow-wise. Spellings still owed.*
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
  commute across stream flows; the commute-variant taxonomy. *Both of
  the two operations the one word names are now **implemented**:
  transpose over a Cross (the poset round) and the directed sequence
  over a stream (`Codegen.emitSequenceCommute`); the stacked stages and
  their shape discipline are what remain.*
- [`case-commute-polarity-design.md`](case-commute-polarity-design.md)
  — the polarity of moving case cells out of a loop, now carrying the
  record's working account of what a case cell *is*: not a flow wire
  but `(payload, %Cell)`, with the ordinary option/complement flows
  (`~Error`, …) derived projections of the cell bundle. Case-cell
  commute is **scope lifting** (`List (A+B) -> A + List B`, witness
  policy part of the law), and a first-witness commute may retain the
  complement prefix — so prefix retention is orthogonal to commuting,
  reopening the boundary with collect-until. The firm results — series
  commutes are priority termination only (and, per the third
  conversation, a *trap*: unanswerable over an unbounded stream, with
  an ill-formedness lean), time-ordered disjunction needs one
  coordinating node, junction commutes are two loops — plus the **jog**
  (shortening commutes displace the flow wire) and **node-local cells**
  leans, and the **drawn, not algebraic** resolution posture. The
  interim co-flow ontology and the identity test as an operation
  boundary are superseded in place. A fourth conversation
  (2026-08-16) adopted the round's first results — the election
  rule, the stream-lean retirement, and the barrier as a fused
  join → commute → split — and a **drafted lifting-law inventory**
  (2026-08-16, exploration) is appended, proposing witness
  selection as an order demand under the owned-order criterion.
  *Open problem, Tier 1; the election rule and barrier expansion
  adopted, the rest unadopted.*
- [`async-flow-design.md`](async-flow-design.md) — the async flow:
  values that arrive later, racing as a barrier, and failure on the
  revised account — rejection as an *arrival* carrying an Ok/Err
  case bundle, stream endings reason-only with diagnoses on value
  wires. *Exploration; its failability sections were re-founded
  2026-08-14 onto the 2026-08-04 revisions (the superseded
  terminator-payload account is recorded in place).*
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
  inventory account. Revised (2026-08-04): the fail node is
  dissolved — its programs draw as split + inferred short-circuit
  commute + collect (short-circuit vs accumulate carried by where
  the alt's collect sits); automatically failable values rejected —
  failure travels a drawn flow wire; the super flow survives; the
  error arm's prefix question pinned. Tag identity across reuse
  boundaries — the residue — carries a worked round of its own (the
  referent rule: a lane's identity is a drawn identification of
  minting sites, never a string; exploration, unadopted). The
  revision's owed re-founding of the inventory is now worked in
  place too ("The inventory re-founded as alt-reach", 2026-08-14:
  one question splits into two — endings reason-only and nearly
  content-free, failure data the existing case-alt property over
  drawn wires and completed commutes, no failure-specific checker
  machinery; exploration, unadopted). The short-circuit commute
  itself is re-founded again by the case-cell account (2026-08-15/16,
  `case-commute-polarity-design.md`): the compact `~Error` rail is a
  derived projection of the cell bundle, the commute a case-cell
  scope lift with the error arm's pinned prefix question reopened as
  prefix-retention-orthogonal-to-commuting; nothing adopted.*
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
  of the top-down/bottom-up duality with saturation. *Mixed: the
  two-ends core adopted (2026-07-23, riding the joint adoption); the
  rest exploration.*
- [`incremental-flow-design.md`](incremental-flow-design.md) — the
  incremental flow (reactive vars): hold/changes, cutoff, and pushing
  values into a "necessity frontier." *Exploration.*

## Compile

- [`lazy-compile-design.md`](lazy-compile-design.md) — the
  runtime-lazy strategy of the earlier compiler (`src/Compile.res`,
  since deleted with the bridge migration); its semantics — runtime
  laziness, per-node memoisation, self-contained collect thunks —
  survive in `Codegen.res`. *Historical.*
- [`compile-strategy-design.md`](compile-strategy-design.md) — the
  compiler as a pipeline of pure passes. *Implemented in shape
  (derive → complete → check → annotate → codegen, `Pipeline.res` —
  the doc's "planned rebuild" happened); its remaining aspirational
  pieces (full multi-level derive, the deferred
  placement/strictness passes) are tracked in
  `src/ARCHITECTURE.md`.*
- [`lazy-stream-placement-design.md`](lazy-stream-placement-design.md) —
  how stream (pull-based, on-demand) flows compile. The committed
  baseline is per-node memoised streams, with the compiler deciding
  nothing about placement — the implemented eager strategy transposed
  to streams; the consumer-set analysis that would merge one conceptual
  loop into one emitted loop is a deferred optimisation, not a
  rejection (see the doc's status header). *Its implementation steps 1,
  2 and 3 — the runtime primitives, the single-output stream flow, and
  the sequence commute — are now **implemented**; see
  `src/ARCHITECTURE.md` worklist item 10 for what landed and what
  step 6 and the stacked stages still owe.*
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
  five seeded-random draws of real code (loops twice, concurrency
  sites, nested-loop sites, previous-value sites), classified against
  the inventory.
  Findings that reweighted the agenda: uncollect/collect is
  the center; early termination is the biggest everyday gap; the
  running-sum scan is rare in infrastructure but dominant in numerics;
  first-of coordination (race/timeout/cancel) outweighs all-of nine to
  one; order-observing consumers over genuine grids run ~10–13% of
  nested-loop sites, their orientation always already authored (the
  product-linearization round's owed check); among carried-state
  loops the seeded feedback register dominates, raw previous-value
  reads are mostly companions of a register, and the position-0
  boundary is always discharged rather than tested (the
  value-in-context model's owed check). Read the tallies with
  the 80/20 counterweight (frequency ranks
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

- [`implementation-strategy.md`](implementation-strategy.md) — the
  original map from the design record to code. *Retired
  (2026-08-12): most of its phases are implemented, and its role is
  carried by `src/ARCHITECTURE.md` (the live record of how the code
  is shaped and what remains); the compiler-specific half of the
  map remains `compile-strategy-design.md`.*

## Layout (out of scope in this repo)

Kept because the layout algorithm should survive, but the graphical side
is out of scope for work here. Each carries a status header noting where
its vocabulary predates the newer rounds.

- [`graph-representation.md`](graph-representation.md)
- [`visual-layout-guidelines.md`](visual-layout-guidelines.md)
- [`rendering-algorithm.md`](rendering-algorithm.md)
- [`program-to-graph-transformation.md`](program-to-graph-transformation.md)
