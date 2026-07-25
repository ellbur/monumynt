# monumynt

An experimental sandbox for a visual flow-based programming language.
The language design lives in the documents under [`plans/`](plans/);
this repository implements the **non-graphical building blocks** — the
data structures and the compile pipeline that the eventual visual
editor would sit on top of. Layout, rendering, and the diagram-editor
side are out of scope here.

The code is ReScript 12 compiled to ES modules and run on Node.

## Design documents

The design work has run well ahead of the code. The code implements
list/option iteration, case splits, join and filter, partial collects,
registers (the Delay pair), the whole-table Cross, and a textual
surface that round-trips; everything else in the design documents is
design-only so far.

**Start with [`plans/README.md`](plans/README.md)** — the index, with
reading order and per-document status. The shortest path in:

- [`plans/language-design-philosophy.md`](plans/language-design-philosophy.md)
  — the seven principles every new construct is evaluated against.
- [`plans/core-model.md`](plans/core-model.md) — the core model in
  current vocabulary: value vs flow wires, uncollect/collect, no time
  travel, binary join, bundles, barriers-not-bottlenecks, the flow
  kinds.

Rejected ideas are recorded in place, in the doc that owns the topic,
each with the reason it must not be pursued again.

The rest, grouped in the index: the data-representation spec and the
textual form; iteration state (the biggest open area — two live
candidates, deliberately undecided); streams, async, and incremental
flow kinds; the partial collect, Cross, time-travel completion, and
transformation levels; validity checking without types; the compile
strategy (implemented and planned); the five tough use cases; and the
implementation sequencing.

## What the code implements

The pipeline:

```
text  ─lex/parse/resolve─┐
                         ├─→  Program (node set + outputs)  ─→  JsAst  ─→  JavaScript source
handles (Build)  ────────┘        derive → complete → check → annotate → codegen
```

- `src/JsAst.res` — typed AST for a useful subset of JavaScript.
- `src/JsPrint.res` — precedence-aware pretty-printer.
- `src/JsBuild.res` — smart constructors so building JsAst reads like
  the JS it produces.
- `src/Program.res` — **the program of record**: the ports-first
  representation. A program is a node set plus distinguished outputs
  (no root expression). Node kinds are `Lit`, `App`, `Uncollect`
  (list / option / case — the opener), `Collect` (the consumer),
  binary `Join`, `Commute`, `Cross`, and the `DelayRead`/`DelayWrite`
  register pair; ports are named value/flow refs, with per-alt ports
  on a case split (no Branch node). Sharing is opt-in via node
  identity: bind once in ReScript, reference twice.
- `src/Build.res` — typed handles over `Program` (strings below,
  typed handles above); also collects the node set, closed by
  `finish(~outputs)`.
- The compile pipeline as pure passes
  (`plans/compile-strategy-design.md`): `Derive` → `Complete`
  (inserts a Cross for a sibling-opens combine) → `Check`
  (well-formedness witnesses returned as data) → `Annotate` →
  `Codegen`, wired by `Pipeline.res`. `Codegen` is a pure
  let-floating placer with a (node, port, context) memo; every node
  becomes a lazy binding and every reference forces, so runtime
  laziness handles "compute only when needed" and "compute only
  once". Rationale in `plans/lazy-compile-design.md`.
- `src/Text*.res` — the textual surface: lexer, parser, resolver
  (into `Build`), and a total printer that round-trips.
- `src/Runtime.res` — the emitted prelude (three lazy helpers).
- `src/Main.res` — the smoke suite (`npm start`): 191 checks that
  build programs from text and handles, compile them, `eval` the
  output, and compare against author-written expected values, plus
  text round-trips. Coverage spans the value fragment, sharing and
  placement, list/option/join flows (multi-collect, nested, flatten),
  case splits and filters, partial collects, registers, and the
  whole-table Cross.

**[`src/ARCHITECTURE.md`](src/ARCHITECTURE.md)** is the deep map:
module status, the decisions taken, and the worklist.

## Running

```bash
npm install         # one-time
npm run build       # rescript compile
npm start           # node lib/es6/src/Main.res.mjs — runs the test suite
```

`npm run dev` for watch mode.

## Possible next steps

None committed to.

The design-vs-code gap is now mapped in code: **architecture-stub
modules** under `src/` (`Stream`, `Async`, `Incremental`, `Cut`, `Fail`,
`CollectFamily`, `Property`, `OrderDemand`, `Boundary`, `Effects`,
`FocusedUpdate`, `Saturation`, `Edit`) stage the types, adopted
decisions, and settled rejections for everything in `plans/` that has a
worked representation but no implementation. See `src/ARCHITECTURE.md`,
"Architecture stubs", for the index. The items below predate that map
and remain live.

- **The poset round** — the context-model generalisation (linear
  prefix → a genuine series-parallel poset) that the remaining
  `Codegen.Todo` gaps wait on: commute (transpose over a Cross),
  cross of non-top-level / non-list axes, the ≥2-axis fiber (a rank-3
  product collected over one axis, leaving a product context
  standing), and partial collect's merged-context computation.
  `Poset.res` has the algebra; `src/ARCHITECTURE.md` worklist item 8
  is the map.
- ~~**`Aggregate`/`Disaggregate`** for struct construction and field
  projection.~~ DONE (as pure value nodes — Aggregate builds an object
  literal, Disaggregate projects one value port per field; both compile
  like an App, let-floated to where the fields jointly live). The textual
  surface for them is still owed (a separate text-surface round).
- **Diagrams as the top-level structure** — the spec's `Diagram`
  type, compiling to a JS function per diagram. Now has a forcing
  argument beyond spec fidelity: a Delay write half can be
  root-unreachable in a complete program, so the program of record
  is a node set, not a root expression
  (`plans/iteration-with-state-design.md`, "What it forces to the
  surface: the program is a node set").
- **Streams, async, incremental** — each a new species in `Annotate`
  + cells in `Runtime.res` + an emitter, per
  `plans/implementation-strategy.md`.
- **Structural tests** — golden-file the generated JS.

## Layout

```
plans/                               design docs — see plans/README.md
src/
  ARCHITECTURE.md                    the compiler map — read this first
  JsAst.res                          typed JS AST
  JsPrint.res                        precedence-aware printer
  JsBuild.res                        smart constructors
  Program.res                        the program of record (ports-first node set)
  Build.res                          typed handles over Program
  Context.res  Poset.res             flow-context (linear path + SP poset)
  Derive.res  Complete.res  Check.res  Annotate.res  Codegen.res   the pipeline passes
  Pipeline.res                       pass orchestration
  Runtime.res                        the emitted prelude
  TextLex.res  TextParse.res  TextAst.res  TextResolve.res  TextPrint.res   the textual surface
  Main.res                           the smoke suite + examples
rescript.json                        ESM output, lib/es6/, .res.mjs suffix
package.json                         "type": "module"
```

`lib/` is gitignored; only `.res` sources are tracked.
