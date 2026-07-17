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
| `Context.res` | working (v0) | Context paths (bundle-provenance sense) computed structurally; prefix-rule merge. Shared by Check, TextResolve, and (later) Annotate. Incomparable = raise, until products land. |

The compile pipeline (`compile-strategy-design.md`; each pass a pure
function with a printable output):

| pass | module | status |
|---|---|---|
| 0 derive | — | not present; no abstract node species exist yet. Reduce-close will be the first catalog entry. |
| 1 check | `Check.res` | **witness surface decided** (records addressed to authored node ids). Implemented: port-exists, write-count, alignment(v0). Stubs with named owners: join-adjacency, productivity, provenance, coverage, flow-borne. |
| 2 complete | `Complete.res` | stub identity; type carries the insertion report. Harvest/solve/realise (Cross for sibling opens) documented in place; heuristic table reserved as versioned data. |
| 3 annotate | `Annotate.res` | write index + species implemented; flow-variable sets and the deferred placement/strictness/consumer-set annotations have their slot reserved. |
| 4 codegen | `Codegen.res` | signature + architecture comments only. |
| (stand-in) | `LegacyBridge.res` | **disposable**: translates `Program` → legacy `Expr` and reuses `src/Compile.res`, so everything runs end-to-end today. Must never grow features; deleted when Codegen lands. |
| entry | `Pipeline.res` | check → complete → annotate → codegen-stand-in → `JsPrint`. Witnesses come back as data (`result`), bridge gaps as `Failure`. |

The text surface (`textual-representation-design.md`):

| module | status | what it is |
|---|---|---|
| `TextAst.res` | working | Surface statement AST — the meeting point of both directions. Grammar-as-implemented is documented in its header. |
| `TextLex.res` | working | Line-oriented lexer; sorted arrows (`->`/`~>`/`-~>`), sigils; indentation never parsed. |
| `TextParse.res` | working (v0 subset) | tokens → TextAst. Owns only the lexically decidable; pointed errors for not-yet-parsed forms (lanes). `+` lines are skipped (derived, never stored). |
| `TextResolve.res` | working (v0 subset) | TextAst → `Program` via `Build`. Pronouns desugar here (P8): single-assignment global names, ordinal taps, the implicit flow stack as chain-local state. No semantic checks — those stay in `Check`, shared with every authoring path. |
| `TextPrint.res` | working (v0, total) | `Program` → text. Total (registers, commute, cross print today) but not yet pretty: one named forward statement per node; chain compression, taps, derived indentation and the span lint are the next printer round. |

`NextMain.res` (`npm run next`) is the smoke suite / playground: text and
handles building identical wiring, eval'd results, round-trips
(`parse(print(p))` wiring-identical, print stable), witness demos, and a
register program that prints but declines to compile.

## What runs today

```
text ──TextLex/Parse──> TextAst ──TextResolve──> Program (node set)
                                       │
Build handles ─────────────────────────┤
                                       ▼
                          Check ─> Complete(id) ─> Annotate
                                       │
                                       ▼
                        LegacyBridge ─> src/Compile.res ─> JsPrint ─> eval
```

Compilable fragment = the legacy compiler's fragment: list/option flows,
case splits, join/filter, multi-close, sharing. Representable-but-not-
compilable (prints, checks): registers, commute, cross, explicit `in`
nesting, partial collects.

## Decisions taken here (all cheap to revisit; recorded so they are
decisions, not accidents)

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
  resolve to Lits; the rebuild need not.
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

## Growth path (each step small, suite kept green)

1. **Parser catch-up**: flow-ref lane groups (case/partial collects
   become parseable — the printer already emits them), then fused lanes,
   `commute out of`, prefix application, `;` multi-resume.
2. **Printer round**: chain compression + taps (port ExprPrint's greedy
   chains), derived indentation, span lint. Then golden-file tests.
3. **Checks**: join-adjacency and flow-borne (both read off Context),
   productivity over the write index, provenance origins with the
   mixing-vs-time-travel classification.
4. **Codegen rebuild** (replaces the bridge; legacy output as golden
   files), then the uncollect/collect rename is complete and the legacy
   modules (`Expr`, `Compile`, `ExprPrint`, most of `Main`) retire.
5. **Completion**: harvest/solve/realise with the versioned tie-breaker
   table; `+` lines in TextPrint; Cross compile (point-indexed table).
6. **Registers**: productivity check + register codegen (`final`), the
   first non-legacy construct to run.
7. Then per `implementation-strategy.md`: partial collect, streams,
   async/incremental.

## Relation to the legacy modules

`src/JsAst.res`, `src/JsPrint.res`, `src/JsBuild.res` are keepers (the JS
backend). `src/Expr.res`, `src/Compile.res`, `src/ExprPrint.res`,
`src/Main.res` are the previous generation: they remain the running
semantic record (80 tests, `npm start`) and the bridge's target, and are
retired at growth-path step 4 — not before, because their behaviour is
the rebuild's spec.
