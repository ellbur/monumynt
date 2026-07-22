# src/next — the next-generation scaffolding

This directory is the **architecture of the rebuild, written as code**:
types, working building blocks, and typed stubs. It exists so the design
in `plans/` can be played with and its problems discovered, not to be
right the first time. Design questions stay in `plans/`; this file only
records how the *code* is shaped and which decisions it took.

It follows the sequencing of `plans/implementation-strategy.md`:
representation first (ports, node set), text surface early (test
leverage), compiler rebuilt as pure passes against that representation.

## Module map

Representation and authoring:

| module | status | what it is |
|---|---|---|
| `Program.res` | working | The program of record: ports-first nodes (`ValuePort`/`FlowPort`), uncollect/collect vocabulary, binary Join, per-alt ports (no Branch), Delay read/write pair, program = **node set + distinguished outputs**. Port inventories, canonical `dump`/`equal`. |
| `Build.res` | working | Typed handles over `Program` ("strings below, typed handles above"). The builder also *collects the node set* — that is how root-unreachable write halves stay in the program. |
| `Context.res` | working (v0) | Context paths (bundle-provenance sense) computed structurally; prefix-rule merge. Shared by Check, Codegen, and TextResolve. Incomparable = raise on the linear path. **First Poset wiring landed**: `pathToPoset` / `crossProduct` / `productsIndex` lift the sibling-combine question to `Poset` — a program's Cross nodes build the product index `Poset.merge` consults. The linear model stays primary for every consumer (the full poset-valued context, e.g. a collect over a crossed axis reporting `{Y}` not `[]`, is the deeper poset round with the emitter). |
| `Poset.res` | working (algebra, unit-tested) | The **series-parallel context** — the poset generalization of the linear path (the Fork-A discussion, ARCHITECTURE poset round). Built by SERIES (nesting) and PARALLEL (Cross) composition, so every well-formed context is SP; the non-SP "N" is a repeated-flow diamond (align-vs-cross unresolved), witnessed not represented. Provides the `≤` primitive (`axes-⊆ + order-extends`) and `merge` (comparable → the deeper; siblings → the **exact-axis** constructed product, not a covering superset — `leq` is monotone `⊆` but a combine's home is `==`, since a flat cross builds no sub-products; else `Incomparable`, the completion gap — an under-determined cross is just another time-travel program). Axis keys are strings — pure, decoupled from Program. Products + nesting only; cells (⊇ polarity) arrive with partial-collect's merged context. **Wired into Context** for the alignment admit (`Context.productsIndex`); the full context-model migration (Cross output ports, poset-valued contexts everywhere) is the rest of the poset round. |

The compile pipeline (`compile-strategy-design.md`; each pass a pure
function with a printable output):

| pass | module | status |
|---|---|---|
| 0 derive | `Derive.res` | honest identity (no abstract node species exist, so every program is level-0). The catalog architecture — pattern/expansion/correspondence, composite ids, the origins map — is recorded in its header for when reduce-close arrives. |
| 1 check | `Check.res` | Implemented: port-exists, write-count, **alignment** (now with the **mixing / time-travel classification** folded in — walks the two incomparable paths to their first divergent step: sibling cells of one split ⇒ `bundle-mixing`, otherwise ⇒ a time-travel candidate that is **admitted iff a constructed Cross covers its exact axes** — `Context.productsIndex` + `Poset.merge` — else ⇒ `time-travel`), **join-adjacency** (an inner operand opens exactly at the outer flow's interior — computed by `Context.flowInterior`, which flattens a Join outer through its stacked layers, so a nested flatten like flatten-then-filter is not wrongly rejected against a single-layer `[outer]`), **invariance** (Cross operands must be mutually invariant — the Cross round's first step, consuming Annotate's flow-variable sets), **flow-borne** (program boundary **and** the general interior rule — a collect branch whose value is borne on a flow it does not iterate, exact for element/alt-payload interiors; Join/Commute/Cross interiors defer to the poset round), **coverage**. Stubs with named owners: productivity; provenance's deferred cell-set remainder (the poset round). |
| 2 complete | `Complete.res` | **the sibling-opens completion landed** — `harvest` → `solve` → `realise` bodies real for the two-lists time-travel gap: `harvest` finds an App spanning two incomparable top-level list siblings (mutually invariant, exact-span, no constructed Cross yet covering them) and demands a `MustCompare`; `solve` dedups by axis pair; `realise` mints a root-unreachable `Cross(left, right)` into the node set. Runs **before** Check (Pipeline), which validates the *completed* program — the inserted Cross gives the combine a product home, so it compiles via the whole-table emitter instead of witnessing. Identity for already-committed programs, so every other witness is unchanged. Still v0: everything past the binary sibling-opens case (dependent-nesting Nests edges, commute-chain lifts, n-ary combines, the canonical heuristic table). |
| 3 annotate | `Annotate.res` | write index + species + **flow-variable sets** (`introducedAxes`/`sourceAxes`/`valueAxes` and the `crossViolation` mutual-invariance demand — the invariance fact, pure structural non-merging walks) implemented; caching those sets in the annotations record and the deferred placement/strictness/consumer-set annotations have their slot reserved. |
| 4 codegen | `Codegen.res` | **machinery real and running**: pure let-floating placement, (node, port, context) memo with prefix reuse, thunk-tagged context instantiation, flow spines. Emitters done: Lit, App (fn as a wire — computed functions work), iter collect (list/option chains with Join, any-list rule), **case collect** (exhaustive if-chain, else-throw), **filter collect** (join(list, case-alt), a unified iter/dispatch level walk — option leading levels skip the absent option per firing, and a **non-trailing dispatch** `join(join(list, case-alt), inner-list)` nests a for-of inside the alt guard to flatten the kept alt's payload, i.e. filter-then-flatmap; conditional push), **partial collect, direct slice** (a merged flow of k covered cells, terminated by a join → multi-cell filter, or alone → option; k-arm non-exhaustive dispatch; leading levels may be list, option, or a case-alt dispatch via the same unified `filterPlan` walk as filter collect — a `join(join(list, option), partial)` skips the absent option per firing, and a `join(join(list, case-alt), partial)` is a filter-then-partial, the k-arm dispatch nested inside the kept-alt guard), **registers** (the Delay pair: mutable accumulator, single-level driving flow — running sum runs), **cross, whole-table** (the binary product of two top-level list axes: one shared point-indexed table built once in the Cross's stored orientation, both collect orders indexing it — the transpose is free, the user's computation runs once per cell; `product-flows-design.md`'s "Compile" / "smallest first step" 2). `Todo`/deferred, each citing its design doc: filter over only option levels (the accumulator-shape question) and its non-trailing-dispatch cousin; commute; n-ary cross (three-plus axes) and cross of non-top-level / non-list axes (the rest of the poset round); partial collect's **merged-context computation** (the doc's `logAndFallback` step — lives at a cell-set context the linear model can't represent, the *same* non-tree generalization as Cross's poset, so bundled with it); registers over a joined/nested/case flow (the Delay ontology open problem); a register `prev` read by a sibling collect (needs shared-loop-skeleton integration). |
| runtime | `Runtime.res` | the emitted prelude (the three lazy helpers) + builders. Grows the stream/async cells later; owns the inline-vs-imported packaging question. |
| (stand-in) | `LegacyBridge.res` | **disposable**: translates `Program` → legacy `Expr` and reuses `src/Compile.res`. Now the *fallback engine* (below). Must never grow features; deleted at retirement. |
| entry | `Pipeline.res` | derive → check → complete → annotate → **two engines** → `JsPrint`. Witnesses come back as data (`result`), engine gaps as exceptions (`Codegen.Todo` / bridge `Failure`). |

The text surface (`textual-representation-design.md`):

| module | status | what it is |
|---|---|---|
| `TextAst.res` | working | Surface statement AST — the meeting point of both directions. Grammar-as-implemented is documented in its header. |
| `TextLex.res` | working | Line-oriented lexer; sorted arrows (`->`/`~>`/`-~>`), sigils; indentation never parsed. |
| `TextParse.res` | working (v0 subset) | tokens → TextAst. Owns only the lexically decidable; pointed errors for not-yet-parsed forms (lanes). `+` lines are skipped (derived, never stored). |
| `TextResolve.res` | working (v0 subset) | TextAst → `Program` via `Build`. Pronouns desugar here (P8): single-assignment global names, ordinal taps, the implicit flow stack as chain-local state. No semantic checks — those stay in `Check`, shared with every authoring path. |
| `TextPrint.res` | working (total + chains) | `Program` → text. Total (registers, commute, cross print today). First pretty round DONE: single-consumer runs fuse into postfix chains, implicit flows drop their `~name`, single-use data literals inline, statements are topologically ordered by name dependency. Still deferred: junction taps (named fan-out stands in), bare `join` in a chain (joins print standalone), derived indentation and the span lint. |

`NextMain.res` (`npm run next`) is the smoke suite / playground: text and
handles building identical wiring, eval'd results (with the engine used
printed per output), automatic differential checks, round-trips, witness
demos, and a register program that prints but declines to compile.
Currently 139 checks.

## The two engines (the migration harness)

Pass 4 has two implementations, and the harness between them is how the
rebuild lands **one emitter at a time with every test running**:

- **NextCodegen** (`Codegen.res`) — the rebuild. An emitter that is not
  written yet raises `Codegen.Todo(msg)`. `Todo` is strictly for gaps;
  `failwith` remains reserved for compiler bugs and ill-formed programs
  Check should have witnessed.
- **Bridge** (`LegacyBridge.res` → `src/Compile.res`) — the disposable
  stand-in, one legacy IIFE per output.

`Pipeline.compile` tries NextCodegen and falls back to the Bridge on
`Todo`, reporting the gap message in `compiled.codegenGap` — so the test
log names exactly which emitter a fallback is waiting on.
`Pipeline.compileVia` forces one engine; `NextMain.expectOutput` uses it
to run the **differential check** automatically: whenever NextCodegen
compiled an output and the Bridge can also compile the program, both are
eval'd and must agree. The legacy suite (80 tests, `npm start`) plus this
differential is the rebuild's spec — write an emitter, watch its tests
flip engines, and agreement is checked without writing new tests.

**Retirement** (was growth-path "codegen rebuild"): when no reachable
program raises `Todo`, delete the fallback arm, `LegacyBridge.res`, and
the legacy modules (`Expr`, `Compile`, `ExprPrint`, most of `Main` —
first snapshot their emitted JS as golden files if output-shape review is
wanted). `Runtime.res` already duplicates the lazy helpers, so retirement
is pure deletion.

## What runs today

```
text ──TextLex/Parse──> TextAst ──TextResolve──> Program (node set)
                                       │
Build handles ─────────────────────────┤
                                       ▼
        Derive(id) ─> Complete ─> Check ─> Annotate
                                       │
                      ┌────────────────┴───────┐
                      ▼            Todo ⇒      ▼
                 Codegen.res ─────────► LegacyBridge ─> src/Compile.res
                      │                        │
                      └───────────┬────────────┘
                                  ▼
                          JsPrint ─> eval (+ differential when both compile)
```

Via NextCodegen today: the value fragment (including **computed
functions** — App's fn is a wire, which the bridge cannot express),
list/option chains with binary Join, multi-close, single-module
multi-output compilation (outputs share one memo), **case collects**,
**filters** (join with a case-alt inner operand, including nested
flatten-then-filter — a Join whose outer is itself a Join stacks its
leading list levels before the dispatch — and **option leading levels**,
where a `join(join(list, option), case-alt)` loops the list, skips the
absent option per firing, and pushes the kept alt; an **all-option
filter** `join(option, case-alt)` has no list, so the any-list rule
makes its output an option — `let out;` set only when the option fires
and the alt matches; and a **non-trailing dispatch** — a filter-then-
flatmap `join(join(list, case-alt), inner-list)` that nests a for-of
inside the alt guard to flatten the kept alt's payload, the one filter
shape the legacy close cannot express), **partial collects**
(the direct slice — a merged flow of k covered cells feeding a filter or
an option, its leading levels list, option, or a case-alt dispatch — the
filter-then-partial `join(join(list, case-alt), partial)` — just like the
filter's),
**registers** (the Delay pair over a single-level
driving flow — the first non-legacy construct to run, so beyond the
bridge and validated against the design docs rather than by the
differential), and the **whole-table Cross** (a binary product of two
top-level list axes, consumed by a two-collect chain in either order —
one shared point-indexed table, both orders indexing it, the user's
computation run once per cell; also beyond the bridge, validated against
hand-built tables and a golden add-once check), and the **completion of a
sibling-opens time-travel program** — the two-lists combine with no
hand-drawn Cross has one inserted by `Complete` (which now runs *before*
Check, so Check validates the completed program), then compiles via the
whole-table emitter to the same values as the hand-drawn form
(product-flows-design.md's "smallest first step" 3). Via the Bridge: nothing
among the smoke tests still falls back. Representable-but-not-compilable
(prints, checks, and now round-trips through the text surface): commute
(its standalone `commute out of` form authorable in text — NextMain 15c),
n-ary / non-top-level-list cross (the rest of
the poset round), explicit `in` nesting, partial collects whose merged
value is *computed at the merged context* (needs the cell-set/poset
round), and registers over joined/nested/case flows (the Delay ontology
open problem).

## Decisions taken here (all cheap to revisit; recorded so they are
decisions, not accidents)

Representation and surface (from the first scaffolding round):

- **Node set from day one.** `Build.finish(b, ~outputs)`; no root
  expression anywhere. Forced by write halves; also the honest signature
  for multi-output diagrams.
- **Port-name scheme**: strings at the representation level; bare alt
  names on both sides, disambiguated by ref sort. (Ports doc open q.1 /
  text doc open q.6 — provisional.)
- **Join is flow-only** at the Expr level (confirmed lean, ports doc
  open q.3). Value crossings stay derived.
- **App fn and case discriminator are wires** (usually to `Lit` externs),
  not embedded JsAst — functions are values. The bridge requires them to
  resolve to Lits; Codegen does not (it forces the fn wire at the call).
- **`js "..."` externs** ride a new `JsAst.ERaw` (prints parenthesized,
  verbatim). The one additive change to the legacy layer.
- **Error surface**: witnesses as records `{nodeId, rule, message}`
  addressed to authored ids; pipeline returns them as data. Raising is
  reserved for compiler gaps/bugs.
- **Write half names its read by node reference** (not a thread port) —
  the recorded spelling question; either works, this is the smaller.
- **Text pipeline meets at TextAst**; resolve (not parse) owns names,
  taps, and the implicit flow stack, which is *chain-local resolver
  state* seeded from Context paths (the naturality note in the text doc).
- **Printer is total before it is pretty**; v0 emits the factored edge
  list (all named, forward), which reparses. Prettiness is a separate,
  focused round (implicitness thresholds, text doc open q.5).

Compile pipeline (this round):

- **Engine fallback + differential is the migration structure.**
  `Codegen.Todo` (gap; Pipeline falls back) vs `failwith` (bug /
  should-have-been-witnessed; never falls back) is a load-bearing
  distinction — a fallback that swallowed bugs would let the two engines
  drift apart silently.
- **Complete runs before Check; Check validates the completed program.**
  The pipeline is derive → **complete → check** → annotate → codegen (not
  derive → check → complete). Completion commits an under-determined
  program — inserting a Cross for a sibling-opens combine — and the
  committed form is what Check gates, so the inserted product turns a
  time-travel gap into a well-formed combine rather than a witness.
  Completion harvests its own demands (it does not read Check's
  witnesses — compile-strategy-design.md open question 6, "keep the
  outputs distinct"), and it is identity for already-committed programs,
  so every non-completable clash (bundle mixing, dependent nesting,
  coverage, flow-borne, invariance) is reported exactly as before. The
  alternative (check first, then complete) was rejected: it would either
  witness the very programs completion exists to fix, or require Check to
  special-case "completable" gaps it then leaves for a later pass.
- **Placement is let-floating, not buffers.** Every compile returns
  statements tagged with the context they must live in; owners (collect
  emitters, the top level) keep what is addressed to them and float the
  rest upward in their own results. Loop-invariant hoisting is the
  default behaviour of floating, not an analysis.
- **Context segments are thunk-tagged.** A codegen context is
  `array<{flow, thunkOf}>` — the structural flow path with each segment
  tagged by the collect whose emitted thunk owns that JS scope. Two
  sibling collects over one flow open structurally identical paths but
  distinct scopes; the tag is what stops a binding emitted inside one
  thunk from being memo-reused in the other (the legacy compiler used
  bodyRef object identity for this; tags are the pure spelling).
  Consequence kept intentionally: per-iteration work still re-emits per
  consuming thunk — the documented cost of the eager model.
- **Memo keys on (node id, port); entries store the instantiated context
  the binding was placed in; lookup reuses on prefix** (the legacy
  `isAncestor` scan, re-plumbed). Lits memoise at the empty context. A
  structural required context (from `Context.res`) is *instantiated*
  against the current chain — a mismatch asserts, per check-and-tag.
  Incomparable-context demands lift to a product context (point-indexed
  table) — that case arrives with the Cross emitter and must stay
  unreachable until the checker admits products.
- **Codegen state is a mutable map scoped to one invocation behind a
  pure interface** — the explicitly-allowed spelling in
  compile-strategy-design.md; `codegen` stays a function of
  (annotations, program).
- **The runtime lives in `Runtime.res`**, duplicated from the legacy
  compiler (not aliased) so retirement is pure deletion. Packaging
  (inline prelude vs imported module) is deferred until streams make the
  prelude non-trivial; meanwhile Pipeline wraps one IIFE per output,
  each carrying the whole module's statements (unused lazies never run)
  — real ES-module packaging is compile-strategy open q.3.

## Fill-in worklist (each item small, suite kept green; written for
whoever picks this up next)

The tracks are independent — any order works. For every codegen emitter:
the legacy function named at the `Todo` is the spec, the differential
check verifies agreement automatically, and the test log's `codegen gap`
line tells you which tests are waiting.

1. **Case collect emitter** — DONE (`Codegen.res`, `emitCaseCollect`,
   the `CaseFull` arm; spec: `Compile.emitCaseClose`). Pre-memoises the
   alt payload port (split id, alt name) at `exterior ++ [alt flow
   tagged with this collect]`; NextMain test 6 runs via NextCodegen and
   the differential validates it.
2. **Filter collect emitter** — DONE (`Codegen.res`,
   `emitFilterCollect`, the `hasAlt` arm of `IterCollect`; spec:
   `Compile.emitFilterClose`). Now a **unified level walk** over the
   spine (`filterPlan` = `FIter` | `FAlt`): iter levels (list for-of /
   option defined-check) and case-alt dispatch levels interleaved in
   **any order**, assembled innermost-out. Leading levels may be **list
   or option** (an absent option skips its firing, contributing nothing
   — mirrors `emitIterCollect`'s per-level for-of / if-defined branch;
   NextMain test 7e, beyond the bridge so hand-validated). The
   **all-option filter** (no list level) is handled too: the any-list
   rule (`lazy-compile-design.md`) makes its output an **option** (`let
   out;` + assign, set only when the option fires and the alt matches)
   rather than a list — the single-alt case of `emitPartialCollect`'s
   collected-alone reading (test 7c), so the two emitters stay
   consistent (NextMain test 7f, hand-validated). The **non-trailing
   dispatch** — an iter level nested *inside* a dispatch, i.e.
   `join(join(list, case-alt), inner-list)`, filter-then-flatmap: for
   each kept alt the emitter nests a for-of inside the alt guard's `if`,
   flattening the alt's payload list (NextMain test 7g, hand-validated —
   a shape the legacy filter close cannot express, its dispatch is always
   innermost). No `Todo` remains in `emitFilterCollect`. Flips test 7;
   differential validates the list-only trailing shapes.
3. **Parser catch-up** (`TextParse.res`): flow-ref lane groups — DONE
   for the labeled form (`~flow: value` lanes + `-~> collect =>` binder;
   `TextParse.parseLaneCollect` → `TextAst.LaneCollect` →
   `TextResolve.resolveLaneCollect` → `Build.collectCases`). Case
   collects now parse, compile, and round-trip (NextMain test 6b); the
   partial form's `~flow` remainder binder is wired but untested (needs
   the partial-collect emitter). **`cross with` DONE** — the standalone
   product statement (`~left ~> cross with ~right => ~flow`,
   `TextParse.parseStage`'s `cross` case → `TextAst.StCross` →
   `TextResolve`'s flow-source combine, mirroring `join into`) parses,
   resolves, compiles (via the whole-table emitter), and round-trips
   (NextMain 15b, both collect orders authored in text). **Infix
   operators DONE** — `+ - * / %` parse as accepted input (source infix
   `a * b` and the chain-position operator section `-> * 2`), desugaring
   to an App of the operator's extern (`TextParse.opInfo` precedence
   climb + `StBinop`; `TextResolve.opToJs`). The double/triple test
   stand-ins are now real inline multiplication (NextMain 2–6b). The
   canonical printer does not yet re-emit infix (design open question
   5), so a round-trip prints the desugared App form. **Prefix
   application DONE** — `f(x, y)` (and nested / curried `f(x)(y)`, and
   mixed with infix `f(x) * 2`) parses as a term via `TextAst.TApp` /
   `TextParse.parseApplied` / `TextResolve`'s `TApp` arm, building the
   same App the postfix stage `x, y -> f` does (the permissive grammar's
   other authoring path converging on one reading). The canonical printer
   emits the postfix form, so a round-trip prints `x, y -> f` (NextMain
   1c, with a prefix≡postfix wiring-identity check). **`commute out of`
   DONE** — the standalone swap statement (`~inner ~> commute out of
   ~outer => cN`, `TextParse.parseStage`'s `commute` case gaining the
   optional `out of ~outer` clause → `TextAst.StCommute({outOf})` →
   `TextResolve`'s flow-source combine, mirroring `join into`) parses,
   resolves, and round-trips; the two-port Commute node binds by name
   (`ECommute`) so its swapped flows resolve as `~cN.outer` / `~cN.inner`
   (a case split's `~cN.<Alt>` projection generalized). Bare `commute`
   stays the chain-position swap of the two innermost open layers.
   Commute is still representable-but-not-compilable (the emitter is the
   poset round's), so NextMain 15c validates by wiring identity, a clean
   check, and the round-trip, not by evaluation. Still ahead of the
   parser: fused lanes, `;` multi-resume. Each remaining form has a
   pointed "not yet parsed" error today.
4. **Printer round** (`TextPrint.res`): chain compression — DONE
   (single-consumer runs fuse into postfix `->`/`-~>` chains; a flow a
   chain opens *and* closes is implicit — no `~name`, the bare `collect`
   reseeds the stack from the value's context; single-use data literals
   inline at their use site; the App-fn / split-disc / output positions
   keep their operand named). The subtle piece is ORDERING: fusing a
   chain onto its head prints it at the head's slot, so a `-~> collect
   ~jN` or a referenced fn literal can end up before the statement that
   binds it — statements are therefore topologically sorted by name
   dependency (a "unit" = head node + the nodes it fuses; edges from any
   cross-unit input; Kahn, ties by node order). NextMain has golden
   assertions (`expectFusedLine`) beside the round-trips. Still deferred
   (kept out to keep the round focused): junction TAPS (`|`) — named
   fan-out is the total, round-tripping stand-in; bare `join` in a chain
   (joins print as the standalone `join into` form); derived indentation
   by flow depth and the span lint; `+` completion lines.
5. **Checks** (`Check.res`): **coverage** — DONE (`checkCoverage`):
   mixed-split / non-alt-multi-branch collects (via `classifyCollect`)
   plus duplicate-alt coverage, turning a case-emitter crash into a
   witness (NextMain test 11). **productivity** — unreachable today (the
   object graph is a DAG by construction; the only cycle is the register
   pairing itself), so left stubbed with that rationale recorded; it
   becomes load-bearing once a representation admits foreign cycles.
   **provenance's mixing-vs-time-travel classification** — DONE, folded
   into `checkAlignment` (bundle-provenance-design.md, "the same check
   with the property refined"): `Context.Incomparable` now carries the
   two flow *paths*, and `classifyClash` walks them to their first
   divergent step — sibling cells of one case split ⇒ `bundle-mixing`
   (hard error, names the split and both cells), otherwise ⇒
   `time-travel` (completable — completion inserts a Cross). NextMain
   tests 10 (`time-travel`) and 10b (`bundle-mixing`). `checkProvenance`
   now carries only the deferred cell-set / subset-lattice remainder
   (the poset round, item 8), where the not-≤ branch splits by the MEET:
   a non-empty meet (`{A,B}` vs `{B,C}` ⇒ `{B}`) is an inferred
   incorporate, not a clash — only a disjoint meet is bundle mixing
   (bundle-provenance-design.md, "Revision: overlap is incorporate, not
   a clash"). **flow-borne's general interior rule** —
   DONE (`checkFlowBorne` + `branchInterior`): a collect branch whose
   value is borne on a flow the collect does not iterate (a sibling
   alt's payload, an unrelated open's element) is now a witness rather
   than Codegen's "flow-borne port reached outside its flow" failwith —
   exact for element / alt-payload interiors (the branch flow targets an
   Uncollect), with Join/Commute/Cross interiors left to the poset round
   (`branchInterior` returns None). NextMain test 12. Remaining: none in
   this pass — these turned the remaining Codegen asserts into
   user-facing witnesses.
6. **Registers** — DONE for the self-driven case (`Codegen.res`,
   `emitRegister`, reached via the `DelayWrite` `final` port). The write
   half doubles as the feedback collect: it emits its own loop skeleton
   with a mutable accumulator (`let reg = force(init)`; `const prev =
   lazyDone(reg)` at body top; `reg = force(step)` at bottom; `return
   reg`). NextMain test 8's decline flipped to a real compile (running
   sum = 6, empty list = init). Remaining: (a) the **productivity
   check** (`Check.res` stub) — currently unreachable, since the object
   graph is a DAG by construction and the only cycle is the register
   pairing itself, so every buildable program is productive; it becomes
   load-bearing once a representation admits foreign cycles. (b) A
   register `prev` **read by a sibling collect** over the same flow —
   the eager model gives each consumer its own loop, so sharing the
   register's mutable state across loops needs the driving collect to
   emit the register `let` into *its* skeleton via `st.ann.writeIndex`;
   deferred (the `DelayRead` arm `failwith`s if `prev` is reached
   outside the write half's loop). (c) Registers over a joined / nested
   / case driving flow — the Delay ontology open problem
   (iteration-with-state-design.md); raises `Todo`.
7. **Retirement** (see "The two engines"): when `Todo` is unreachable,
   delete the fallback, the bridge, and the legacy modules.
8. **The poset round** (deferred together, because they are one
   context-model generalization — linear prefix → a genuine poset with
   non-tree segments). **Front half started**: Cross's "smallest first
   step" 1 — the **invariance fact** — is DONE (`Annotate.res` flow-
   variable sets: `introducedAxes`/`sourceAxes`/`valueAxes`; `Check.res`
   `checkCross`, rule `invariance`; NextMain test 13). Pure non-merging
   walks, so the demand is answerable on the two *incomparable* flows a
   Cross combines — the one fact the linear context model can't supply.
   A dependent nesting (inner source varies with the outer element) is
   witnessed; top-level siblings and siblings that share an outer loop
   both pass (the demand tests source-vs-own-axis, not raw set overlap).
   **Context representation started**: the context model is a **series-
   parallel poset** (`Poset.res`), settled on paper (recorded in the
   session's Fork-A discussion) — nesting = SERIES, Cross = PARALLEL, so
   every well-formed context is SP; the non-SP "N" is always a
   repeated-flow diamond (align-vs-cross, i.e. zip-vs-Cross, left
   unresolved) and is witnessed, never represented, which makes SP the
   *complete* model rather than a convenient restriction. The `≤`
   primitive (`axes-⊆ + order-extends`) and the LUB `merge` (least
   *constructed* product above two siblings, else `Incomparable`) are
   implemented and unit-tested (NextMain test 14). **First wiring
   landed**: `Context.productsIndex` builds the product index from the
   program's Cross nodes (`crossProduct` = `Poset.parallel` of the two
   operands' full contexts), and `checkAlignment` now consults
   `Poset.merge` so a valid sibling Cross ADMITS its combine while a
   wrong-axes / missing / bundle-mixing clash still witnesses (NextMain
   test 13b). **The whole-table emitter landed** (Cross's "smallest first
   step" 2): `Codegen.res` `emitProductChain` / `getOrBuildTable`
   compiles the binary product of two top-level list axes consumed by a
   two-collect chain — one shared point-indexed table built once in the
   Cross's stored orientation (index-based loops, `cForArr`), both
   collect orders indexing the same `force(table)[i][j]`, so the
   transpose is free and the user's computation runs once per cell
   (`product-flows-design.md`'s "Compile"; NextMain test 15, with a
   golden add-once check and hand-built expected tables — beyond the
   bridge). The routing is `matchProductChain` (recognises
   `collect(fOuter, collect(fInner, s))` over one product with `s`
   spanning both axes); non-product programs are untouched, and a
   product value's App — whose args are on incomparable sibling axes, so
   `Context.valueContext` raises `Incomparable` — is placed at the
   current (product) context rather than asserting. Still deferred (the
   context-model generalization proper): **n-ary products** (three-plus
   axes) and cross of **non-top-level / non-list axes** (both raise
   `Todo` today — the general poset-valued context, Cross output ports
   for the barrier shape, and the "collect over a crossed axis reports
   `{Y}`" context report land with them); Check admitting products in
   more shapes; **commute** (transpose over a
   Cross — lawful only there, `lazy-stream-commute-design.md`); and
   partial collect's **merged-context computation** (the cell-set /
   subset-lattice segment, the *same* non-tree feature — `product-flows-
   design.md`'s "the first non-tree feature: partial-collect's subset
   lattice"). The Delay-over-products case rides on this too.
   **Completion inserts a Cross** (Cross's "smallest first step" 3) is
   DONE for the binary sibling-opens case (`Complete.res`
   `harvest`/`solve`/`realise`; NextMain test 10): the two-lists combine
   authored with no Cross now has the exact `Cross(X, Y)` inserted and
   compiles via the whole-table emitter, the same values as the
   hand-drawn form. `Complete` runs before Check (Pipeline), so Check
   validates the completed program; completion is identity for
   already-committed programs, and non-completable clashes (bundle
   mixing, dependent nesting, n-ary) are never harvested and stay
   witnesses. Still ahead: dependent-nesting `Nests` edges from
   terminations, commute-chain lifts, n-ary combines, the canonical
   heuristic table, and TextPrint's `+` lines.
9. **Partial collect** — DONE for the direct slice (`Codegen.res`,
   `emitPartialCollect`, plus a `PartialLevel` in `spine`, the flow-borne
   merged-value context in `Context.res`, and the `~pf` lane binder in
   the text pipeline): a merged flow of k covered cells terminated by a
   join (multi-cell filter) or alone (option), k-arm non-exhaustive
   dispatch, merged value consumed directly. Leading levels may be list,
   option, **or a case-alt dispatch** — the leading-level walk is now the
   unified `filterPlan` (`FIter`/`FAlt`) shared with `emitFilterCollect`,
   so a `join(join(list, option), partial)` nests the dispatch inside the
   list's for-of and the option's defined-check (skipping an absent option
   per firing; NextMain test 7d), and a `join(join(list, case-alt),
   partial)` is a **filter-then-partial** — keep the alt, then partial-
   collect a subset of a second split over the kept payload, the k-arm
   dispatch nested inside the kept-alt guard (NextMain test 7h). NextMain
   tests 7b/7c/7d/7h; beyond the bridge, so validated against hand-computed
   values. Still `Todo`: a leading `PartialLevel` (a partial feeding a
   partial — the merged-flow-into-merged-flow shape, the cell-set / poset
   round's). Merged-context computation deferred to item 8. Then per
   `implementation-strategy.md`: streams, async/incremental — each a new
   species in `Annotate` + cells in `Runtime.res` + an emitter, not a
   restructuring.

## Relation to the legacy modules

`src/JsAst.res`, `src/JsPrint.res`, `src/JsBuild.res` are keepers (the JS
backend). `src/Expr.res`, `src/Compile.res`, `src/ExprPrint.res`,
`src/Main.res` are the previous generation: they remain the running
semantic record (80 tests, `npm start`), the Bridge's target, and the
spec for every Codegen emitter (named per stub) — retired at worklist
item 7, not before.

**Planned end state: no legacy/next separation.** The `next` generation
is meant to fully supersede the previous one, not sit beside it forever.
Once Codegen has no `Todo` stubs (the Bridge's whole reason to exist),
the intent is to collapse the split entirely: retire `LegacyBridge` and
the `Pipeline` fallback, migrate the legacy suite's coverage into the
`next` pipeline (the `Main.res` tests become `next` programs — this is
also where its remaining `double`/`triple` AST fixtures get rewritten as
real inline operators), delete `Expr`/`Compile`/`ExprPrint`/`Main`, and
move `src/next/` up to `src/`. Until then the two coexist by design (the
legacy suite is the spec the rebuild is checked against); the note is
here so the coexistence stays a transition, not a permanent shape.
