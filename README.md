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
list iteration, case splits, option iteration, join, and filter;
everything else in the design documents is design-only so far.

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
visual-language Expr   →   JsAst   →   JavaScript source string
   (built in ReScript)    (typed)        (pretty-printed, eval'd in tests)
```

- `src/JsAst.res` — typed AST for a useful subset of JavaScript.
- `src/JsPrint.res` — precedence-aware pretty-printer.
- `src/JsBuild.res` — smart constructors so building JsAst reads like
  the JS it produces.
- `src/Expr.res` — the visual-language expressions: `Lit`, `App`,
  `Open` (list iter / case split / option iter), `Close`, `Branch`,
  value-port references (`ValuePort` — every value input position
  takes one; smart constructors return `{node, value}` handles),
  and flow references (`NodeFlow`, `Joined`, `Filtered`). Sharing is
  opt-in via node identity: bind once in ReScript, reference twice.
  The file's header comment is the reference for how the pieces fit.
  (The design-level names are uncollect/collect. Step 1 of the
  first-class-ports migration is in; under its later steps the
  wrapper flow references become binary Join nodes and Branch
  dissolves into per-alt ports.)
- `src/Compile.res` — compiles an Expr to JS. Every node becomes a
  lazy binding; every reference forces; runtime laziness handles
  "compute only when needed" and "compute only once". Design
  rationale in `plans/lazy-compile-design.md`; mechanics in the
  source comments.
- `src/ExprPrint.res` — human-readable, time-forward rendering of an
  Expr for test logs (`->` chains, `#N` labels for shared nodes).
- `src/Main.res` — the test runner: 80 tests that build an Expr,
  print it, compile it to an IIFE, `eval` it, and compare against an
  expected value. Coverage spans the value-only fragment, sharing,
  list flows (multi-close, nested, joined, mixed), case splits,
  filters, option flows, and mixed case+filter closes on one split.

## The next generation (`src/next/`)

The rebuild the design record calls for has started as scaffolding
under `src/next/`: the ports-first representation (program = node set +
outputs, binary Join, per-alt ports, the Delay pair), a parser and a
total printer for the textual form, and the compile pipeline as typed
passes (check with witnesses; complete/annotate/codegen stubbed, with a
disposable bridge to the legacy compiler so programs run end-to-end
today). **`src/next/ARCHITECTURE.md`** is the map: module status, the
decisions taken, and the growth path. `npm run next` runs its smoke
suite.

## Running

```bash
npm install         # one-time
npm run build       # rescript compile
npm start           # node lib/es6/src/Main.res.mjs — runs the test suite
```

`npm run dev` for watch mode.

## Possible next steps

None committed to.

- **First-class ports, steps 2–4.** Step 1 (`ValuePort` refs in
  every value input position, `{node, value}` handles) landed
  2026-07-10. Remaining, per the staged migration in
  `plans/first-class-ports-design.md`: per-alt ports dissolving
  Branch (step 2), binary Join nodes dissolving the
  `Joined`/`Filtered` wrappers (step 3), and the cheap validity /
  join-adjacency checks (step 4) — the enablers for compile-time
  well-formedness checks and cleaner case-split flows.
- **Well-formedness checks.** Time-travel detection (`deeper` on
  unrelated scopes) and closed-scope leakage are currently trusted,
  not checked. (Per `plans/time-travel-programs-design.md`, detection
  is also the front half of *completion* — some findings become
  insertions rather than errors.)
- **Partial conditionals.** Design worked out in
  `plans/partial-collect-design.md` (no new open construct needed;
  the new node is the partial collect); implementation lands after
  first-class-ports migration step 2.
- **`Aggregate`/`Disaggregate`** for struct construction and field
  projection.
- **Loop-carried state** — implement the register pair from
  `plans/iteration-with-state-design.md`. (The 2026-07-10
  equivalence round there showed the two candidates are one
  construct at the result level, so the pair serves both; the
  authoring-surface choice stays open.) The back-edge construction
  is worked out in `plans/first-class-ports-design.md` ("the write
  half is a node"): the object graph stays a DAG, and the pair
  supplies the previously missing `final` readout.
- **Diagrams as the top-level structure** — the spec's `Diagram`
  type, compiling to a JS function per diagram. Now has a forcing
  argument beyond spec fidelity: a Delay write half can be
  root-unreachable in a complete program, so the program of record
  is a node set, not a root expression (first-class-ports doc,
  "the program is a node set").
- **Structural tests** — pin outer-stmt counts, golden-file the
  generated JS.

## Layout

```
plans/                               design docs — see plans/README.md
src/
  JsAst.res                          typed JS AST
  JsPrint.res                        precedence-aware printer
  JsBuild.res                        smart constructors
  Expr.res                           visual-language expressions
  ExprPrint.res                      human-readable Expr rendering
  Compile.res                        Expr → JS
  Main.res                           test runner + examples
rescript.json                        ESM output, lib/es6/, .res.mjs suffix
package.json                         "type": "module"
```

`lib/` is gitignored; only `.res` sources are tracked.
