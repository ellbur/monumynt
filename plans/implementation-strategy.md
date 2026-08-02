# Implementation Strategy

The design record has run well ahead of the code, deliberately —
foundations before features. This document is the map back. For each
design document it records what is decided, what implementation will
force to be made concrete, and what blocks what; it ends with a
proposed sequencing. Nothing here re-decides a design question. Where
a question is open, the job is to *carry it to the point where code
can decide it*, not to close it on paper. The compiler-specific half
of this map lives in `compile-strategy-design.md`; this document is
the wider frame.

Scope: the graphical/layout side is out of scope in this repo.
"Implementation" below means the non-visual building blocks —
representation, checks, compile pipeline, runtime, text surface.

## Where the code is, where the design is

The code implements: list/option iteration, case splits, join,
filter, multi-close, sharing by node identity, and a runtime-lazy
compile to JS — about the first fifth of the design record. The
record additionally holds, in various states of doneness: first-class
ports, partial collects, completion of time-travel programs, stream
flows with join/commute, loop-carried state (two candidates), async
and incremental flow kinds, a property-based checking substrate,
multi-level programs on a step-DAG, and a textual surface. Beyond that
sits narrative-stage material (trees, reusable diagrams, config
scopes, concurrency, custom flows) that has no starting-point document
yet.

Each subject in the record gets a starting-point document that works
out what falls cleanly out of existing design, lays out options where
a real choice exists, and records the rest as open questions. Most end
with a genuinely small "smallest first step." Implementation should
consume those first steps in dependency order.

## The five workstreams

Everything in the record sorts into five threads that can move
somewhat independently.

**A. Representation.** The shape of the program of record. Sequence:
first-class ports (designed, staged, ready) → the node set / minimal
Diagram entry point (forced by register write halves and multi-output
nodes; an interim spelling is acceptable) → the step-DAG as stored
structure (designed in `transformation-levels-design.md`, but *not
needed for anything currently planned to run* — compilation is a
function of a version; defer until history operations are wanted).

**B. The compile pipeline.** The functional rebuild:
derive → check → complete → annotate → codegen → print, per
`compile-strategy-design.md`. This replaces the architecture in
`src/Compile.res` while reproducing its emitted shapes.

**C. The runtime.** Today, three inlined helpers (`__lazy__`,
`__lazyDone__`, `__force__`). To come, in dependency order (the async
document's own ordering): stream cells (`Delayed`, `SNil`/`SCons`,
`zipStream`, `listToStream`, with the two hard requirements already
recorded — iterative force and path compression) → async cells
(`__asyncCell__`/`__startAsync__`) → async streams / race / interrupt
→ incremental cells plus the two boundary adapters (`hold`, `changes`)
and the generation word. One substrate, grown in layers. Registers
need no runtime at all — they compile to a `let` in the loop skeleton.

**D. Checks.** The tier-2 program, in order: flow-context alignment
first (the smallest first step of *both* `types-design.md` and
`time-travel-programs-design.md` — detection is the front half of
completion) → bundle provenance's one extra clause (origins on context
paths; mixing vs time-travel classification) → shape propagation over
a small demands/offers catalog → the schematic-source (placeholder)
node kind. All are pure analyses over the ports representation; all
produce witnesses addressed to authored nodes.

**E. The text surface.** `TextPrint` first. A total, canonical printer
is pure leverage: golden-file tests for every pass output (including
completion's `+` lines, whose format is already specified), readable
diffs when codegen changes, and a forcing function for the
printer-side open questions (implicitness thresholds, indentation
fallback). `TextParse` follows, when round-trip tests become worth
their cost.

## Doc-by-doc: what implementation must make concrete

### `first-class-ports-design.md` — ready; go first

The most implementation-ready document in the record: a staged
migration (valueRef → alt ports dissolving Branch → binary Join
dissolving the wrappers → opportunistic checks), each step keeping the
80 tests green. Step 1 has landed — valueRef in every value input
position, `{node, value}` handles, 80 tests green with byte-identical
emitted JS. What code must still settle: the port-name scheme (bare
alt names vs `(alt, Value)` pairs — must match the spec's
`outputName`), and the handle-layer ReScript shape (records vs
modules; Warning 30 discipline). Nearly everything else queues behind
this: the checks need wires with structural sources, the barriers need
per-contender ports, partial collect lands "after step 2," and the
Delay pair presupposes step 1.

### `compile-strategy-design.md` — the rebuild

See that document. The one sequencing note that belongs here: do the
ports migration *first*, as designed (it was staged to be mechanical
against the current compiler), then rebuild the compiler against the
ports representation. Rebuilding first and migrating second does the
walk twice; doing both at once is too big a step. The rebuild is also
the natural moment for the Open/Close → uncollect/collect rename and
for switching the entry point to a node set with distinguished
outputs.

### `time-travel-programs-design.md` — completion

The smallest first step is concrete: (1) the alignment check, (2)
directed completion for sibling list opens as an Expr→Expr pass with
the insertion report in test output, (3) canonical option-outward
commute, deferred to streams. What code must make concrete: the
constraint-harvest data structure (directed edges from terminations
and authored joins; undirected comparability edges from combining
nodes), the solver (partial-order extension with the published
tie-breakers — start as a literal ordered array in code, versioned
with the language), and the insertion-report format (ExprPrint first,
TextPrint's `+` lines when workstream E lands).

One revision is settled: for sibling opens the inserted operator is a
**Cross**, not an Incorporate, and disposition 4 mostly dissolves
(`product-flows-design.md`). An Incorporate would erase the two opens'
mutual independence; Incorporate remains the completion for bringing a
*value* into a flow context.

### `product-flows-design.md` — the Cross node

The mutual-constant relationship between sibling flows, as a
construct: a flow-only Cross node (ports like Join/Commute), mutual
invariance as its demand, commute made lawful over crossed pairs (the
transpose), and the point-indexed table as its compile target. The
smallest first step is in the document (invariance fact → node +
whole-table compile → completion inserts it → partial products with
the filter round). What code must settle: the oriented-vs-symmetric
storage lean (represent oriented, read symmetric — with a recorded
exit), the product segment in context paths (the provenance poset),
and naming. Depends on ports (Cross is a flow node) and threads
through phases 3–4 below.

### `types-design.md` + `bundle-provenance-design.md` — checks

The check *logic* is worked out; what's missing is representational:
the catalog schema — the concrete record by which a node kind declares
demands and offers (and by which the handful of App functions used in
tests register theirs) — and the error surface: how a witness is
returned (a result variant, per the runner's needs) and printed. The
schema now has its design round (`catalog-schema-design.md`,
exploration: referent-identified entries, per-family facts, graded
trust); the ReScript shape of an entry is deliberately left as that
round's decide-in-code question, constrained but not dictated. That
error surface is the first place error *content* matters in the repo
and sets the pattern for everything after; it is worth a deliberate
half-day, not an afterthought. Naming questions ("type," "merge") can
stay open — they gate user-facing words, not code.

### `partial-collect-design.md` — after ports step 2

The Expr shape is already written down (`CollectCase` with
`{value, flow}` branch pairs; port inventory read off coverage), the
three compiled arm shapes are specified, and the algebra is three
theorems. The one deferred decision implementation will force: the
OptionIter None-port question (filter-only vs two-cell split; the
document leans two-cell). Small and self-contained — good early
validation that the ports representation carries its weight.

### `lazy-stream-*.md` (placement, join, commute) — streams

The baseline is decided (Shape C, no placement), the runtime
primitives are specified with their two hard requirements, and the
staged implementation order in `lazy-stream-placement-design.md`
stands — with steps 4–5 (consumer-set bookkeeping) explicitly moved
off the critical path into the deferred-but-committed optimisation
(deferred, *not* rejected). What code must settle: runtime packaging
(inline prelude vs imported module — the prelude stops being three
lines here), whether commute becomes a binary node like join (open in
two documents; the ports representation gives it a home, and
implementing commute is when it must be answered), and what collecting
an option flow yields (shared open question with partial-collect; also
forced here).

### `iteration-with-state-design.md` (+ the ports doc's register section)

The record deliberately keeps two candidates side by side — the Delay
pair vs the latent-flow augmented uncollect — and nothing here closes
that. But the two are not equally implementable today. The Delay pair
has a worked representation (read half / write half, DAG
unconditionally, `final` as the write's output), a worked
well-formedness check (productivity), a worked compile target (the
register core: init-before, read-at-top, write-at-bottom,
final-after), and a forcing consequence already absorbed (node-set
entry).

The equivalence between the two is now proven at result level
(`iteration-with-state-design.md`, "The equivalence, worked"): the
latent form's feedback collect *is* the write half, so the two
candidates are one register pair under two drawings. This de-risks the
honest proposal — implement the Delay pair as *compiler substrate*,
which is what the latent form and a future state-thread rendering both
lower to — because the pair no longer puts a thumb on the scale: it is
both candidates' result form. What substrate gravity can still
prejudge is the *surface* question (which drawings exist, which is
primary), and that stays open exactly as the record wants. So the
substrate proposal is flagged here as a decision to accept or reject,
not a plan.

Reduce-close rides with this round (it needs the loop skeleton and
brings the operator-identity registry, which must then get its
concrete form: registry vs node property).

### `transformation-levels-design.md` — multi-level

The compiler-facing slice is small and lands with the first abstract
node: the catalog entry as a ReScript value (pattern — the node
species; expansion — a function producing level-0 structure; port
correspondence — the pairing), the derive pass consuming it,
`DerivedPort` resolution, and deterministic internal ids
(`(host id, internal name)` composites, per the compile document).
Reduce-close is the natural first entry — `expand` on it is fully
specified down to the port list. The rest of the document (step-DAG
storage, materialize, undo, cherry-pick, merge) is *not* on the
compilation path and should wait for a reason to exist in code; what
must be protected meanwhile is only determinism and the id discipline,
so the step-DAG can arrive later without invalidating anything.

### `async-flow-design.md` / `incremental-flow-design.md` — later kinds

Both are semantically settled at the level implementation needs to
start (async cell, start-is-synchronous, barriers as the
representation of race/concurrent-join; incremental's pull baseline
with the generation word, hold/changes as kind-crossing nodes). Both
are gated on streams (runtime order) and on ports (barrier
representation — the blocker the ports document dissolves, though the
barrier constructs still need their own Expr shape round). Decisions
implementation will force: "do bodies raise?" (JS auto-converts throws
to rejections, erasing the infallible/failable distinction — genuinely
open; now carrying a worked exploration, `failure-payloads-design.md`:
failure is drawn, declared throws convert by catalog row, undeclared
throws are edge breaches), event-source retention policy, and the
test-runner story (the
current `eval` + `JSON.stringify` harness is synchronous; async tests
need an awaited variant). Incremental's pure-pull first implementation
is deliberately the degenerate case of the hybrid; the push machinery
is designed but explicitly deferred (pure bodies make the two
observably identical).

### `textual-representation-design.md` — the printer path

Decided enough to build the printer: canonical forward form, three
arrows, graded references, `+` lines, derived indentation. The
concrete path is in the document: `TextPrint` over today's Expr →
round-trip tests later with `TextParse`. What the printer forces:
implicitness thresholds and the `@id` convention for tests. Worth
pulling *early* in the sequence — it has no dependencies beyond the
representation it prints, and every other workstream's testing gets
cheaper once pass outputs print canonically.

### The narrative tail (now the topic docs)

Trees/zippers (`trees-and-recursion.md`), reusable diagrams with
interface summarisation (`functions-design.md`), configuration scopes
and slots (`configuration-scopes.md`), concurrency pools and
custom/effect flows (`custom-flows.md`): design-narrative only. Each
needs its own starting-point document before any implementation claim.
(The divide-flow half of the trees area now has one —
`divide-flow-design.md`, exploration; the zipper/data half is still
narrative-stage.)
None is on the near path, and nothing on the near path blocks on them
— with one exception: *diagrams as top-level structure* is pulled
forward in minimal form (a node set with distinguished outputs) by the
register work, without slots or reuse.

## Proposed sequencing

Baby steps, each leaving the suite green, each independently landable.
Order within phases is argued above; order *across* phases 5–8 is
flexible.

1. **Ports migration, steps 1–3** (+ the cheap step-4 checks).
   Representation first; everything anchors to it.
2. **TextPrint.** Early, for test leverage everywhere after.
3. **The compiler rebuild** on the ports representation: functional
   pipeline, node-set entry, vocabulary rename, same emitted shapes
   (golden-filed via TextPrint/JsPrint).
4. **Checks + completion:** flow-context alignment with witnesses →
   provenance origins and the mixing/time-travel split → the Cross
   node with its whole-table compile → directed completion for sibling
   opens (inserting Cross, per `product-flows-design.md`), insertion
   report in test output.
5. **Streams:** runtime primitives (iterative force, path compression)
   → single-output stream flow → commute (deciding binary-or-not and
   the option-collect question) → stream join.
6. **Registers + first catalog entry:** Delay pair, productivity
   check, register codegen, `final`; reduce-close with `expand` as the
   first derive-pass client; operator identities.
7. **Partial collect** (any time after phase 3; listed here only
   because its None-port decision benefits from the checks existing).
8. **Async, then incremental:** async cells and the failable
   terminator → race/interrupt barriers (their Expr shape round
   happens here) → incremental pull baseline with hold/changes.
9. **Deferred-but-committed:** the placement/strictness pass for eager
   flows and the consumer-set lattice for streams — after the
   semantics above settle. Deferred, not conditional.

The test story stays `Main.res`-shaped throughout: build, print (Expr
and Text), compile, eval, compare — extended with golden files for
generated JS, completion tests that assert compiled-completion ≡
hand-completed-program (commitment 1 as a test), witness tests for
each clash class, and an awaited variant of the runner when async
lands.

## Cross-cutting loose ends

Collected so they don't hide inside individual documents; each names
its home.

- **Error/witness surface** — result type, printing, and the
  addressed-to-authored-ids discipline (types doc; first needed in
  phase 4).
- **Runtime packaging** — inline prelude vs module import
  (compile-strategy doc, open question 3; forced in phase 5).
- **Effects × per-context duplication** — the compile document's open
  question 1; must be resolved during phase 8 design, not discovered.
- **Naming rounds** — uncollect/collect in code (phase 3);
  filter-as-sugar survival (ports step 3 exit); "commute vs sequence,"
  user-facing "type," "time travel program" — all gate user-facing
  text only.
- **Heuristic order and canonical table versioning** — language
  semantics, versioned as such (time-travel doc, open questions 1–2);
  the code should carry them as explicit, ordered, versioned data from
  the first completion commit so the discipline is structural.
- **Id determinism** — composite ids for derived/inserted nodes
  everywhere a pass manufactures structure (compile-strategy doc);
  protects idempotent recompiles and the future step-DAG.
- **Test-runner asynchrony** — `eval`/`JSON.stringify` can't roundtrip
  promises; needed for phase 8 (async doc).
- **The two iteration-state candidates** — the substrate proposal
  above is a flagged decision, not a default; take it up explicitly
  before phase 6.
