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
| `Context.res` | working (v0) | Context paths (bundle-provenance sense) computed structurally; prefix-rule merge. Shared by Check, Codegen, and TextResolve. Incomparable = raise, until products land. |

The compile pipeline (`compile-strategy-design.md`; each pass a pure
function with a printable output):

| pass | module | status |
|---|---|---|
| 0 derive | `Derive.res` | honest identity (no abstract node species exist, so every program is level-0). The catalog architecture — pattern/expansion/correspondence, composite ids, the origins map — is recorded in its header for when reduce-close arrives. |
| 1 check | `Check.res` | Implemented: port-exists, write-count, alignment(v0), **join-adjacency**, **flow-borne(v0: outputs)**. Stubs with named owners: productivity, provenance, coverage; plus flow-borne's general interior rule (noted at the check). |
| 2 complete | `Complete.res` | **pass shape real** — `harvest` → `solve` → `realise` with contracts stated and the constraint vocabulary typed — all bodies v0-trivial (no constraints harvested ⇒ identity). Heuristic table reserved as versioned data. |
| 3 annotate | `Annotate.res` | write index + species implemented; flow-variable sets and the deferred placement/strictness/consumer-set annotations have their slot reserved. |
| 4 codegen | `Codegen.res` | **machinery real and running**: pure let-floating placement, (node, port, context) memo with prefix reuse, thunk-tagged context instantiation, flow spines. Emitters done: Lit, App (fn as a wire — computed functions work), iter collect (list/option chains with Join, any-list rule). `Todo` stubs, each citing its legacy spec function: case collect, filter collect, partial collect, commute, cross, registers. |
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
| `TextPrint.res` | working (v0, total) | `Program` → text. Total (registers, commute, cross print today) but not yet pretty: one named forward statement per node; chain compression, taps, derived indentation and the span lint are the next printer round. |

`NextMain.res` (`npm run next`) is the smoke suite / playground: text and
handles building identical wiring, eval'd results (with the engine used
printed per output), automatic differential checks, round-trips, witness
demos, and a register program that prints but declines to compile.
Currently 32 checks.

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
        Derive(id) ─> Check ─> Complete(v0) ─> Annotate
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
list/option chains with binary Join, multi-close, and single-module
multi-output compilation (outputs share one memo). Via the Bridge: case
collects and filters. Representable-but-not-compilable (prints, checks):
registers, commute, cross, explicit `in` nesting, partial collects.

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

1. **Case collect emitter** (`Codegen.res`, the `CaseFull` arm; spec:
   `Compile.emitCaseClose`). Shape is described at the stub. Pre-memoise
   the alt payload port (split id, alt name) at context `exterior ++
   [alt flow tagged with this collect]`. Flips NextMain test 6 to
   NextCodegen; differential validates it.
2. **Filter collect emitter** (`Codegen.res`, the `hasAlt` arm of
   `IterCollect`; spec: `Compile.emitFilterClose`). The spine already
   delivers the `AltLevel` with split and alt. Flips test 7.
3. **Parser catch-up** (`TextParse.res`): flow-ref lane groups (case /
   partial collects become parseable — the printer already emits them),
   then fused lanes, `commute out of`, prefix application, `;`
   multi-resume. Each form has a pointed "not yet parsed" error today.
4. **Printer round** (`TextPrint.res`): chain compression + taps (port
   ExprPrint's greedy chains), derived indentation, span lint. Then
   golden-file tests.
5. **Checks** (`Check.res` stubs): productivity over
   `Annotate.writeIndex`; provenance origins with the mixing-vs-
   time-travel classification; coverage; flow-borne's general interior
   rule (each stub names its design doc). These turn Codegen asserts
   into user-facing witnesses — do them before or with item 6.
6. **Registers**: productivity check + register codegen (`DelayRead` /
   `DelayWrite` in `Codegen.res` — the driving collect's emitter must
   emit the register `let` into its loop skeleton via
   `st.ann.writeIndex`; `final` readable after). First non-legacy
   construct to run; NextMain test 8's decline flips to a real compile.
7. **Retirement** (see "The two engines"): when `Todo` is unreachable,
   delete the fallback, the bridge, and the legacy modules.
8. **Completion**: `harvest`/`solve`/`realise` bodies in `Complete.res`
   (constraint vocabulary already typed there); `+` lines in TextPrint;
   Cross emitter (point-indexed table, `product-flows-design.md`) —
   which is also what lets Check admit products instead of raising
   `Incomparable`.
9. Then per `implementation-strategy.md`: partial collect, streams,
   async/incremental — each a new species in `Annotate` + cells in
   `Runtime.res` + an emitter, not a restructuring.

## Relation to the legacy modules

`src/JsAst.res`, `src/JsPrint.res`, `src/JsBuild.res` are keepers (the JS
backend). `src/Expr.res`, `src/Compile.res`, `src/ExprPrint.res`,
`src/Main.res` are the previous generation: they remain the running
semantic record (80 tests, `npm start`), the Bridge's target, and the
spec for every Codegen emitter (named per stub) — retired at worklist
item 7, not before.
