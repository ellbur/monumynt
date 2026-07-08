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
everything else in the documents below is design-only so far.

[`plans/visual-language-description/`](plans/visual-language-description/)
describes the language itself:

- `flow_language_design.md` and `visual-flow-language.md` — the core
  idea (blocks turned inside out: control flow as explicit flow
  wiring, not scoped containment) and the full design narrative
  through list operations, case splits, trees, functions, custom
  flows, configuration scopes, concurrency, and commuting.
- `visual-language-spec.md` — the data-representation spec: diagrams,
  nodes, ports, value wires vs flow wires.
- `iteration-rails-design-notes.md` — how values carried between
  iterations are drawn and named.
- `graph-representation.md`, `program-to-graph-transformation.md`,
  `visual-layout-guidelines.md`, `rendering-algorithm.md` — the
  visual/layout side (not worked on in this repo).

[`plans/`](plans/) (top level) holds the design explorations:

- `language-design-philosophy.md` — the six principles every new
  construct is evaluated against.
- `iteration-with-state-design.md` — loop-carried state, narrowed to
  two candidates deliberately kept side-by-side (the Delay node and
  the latent-flow augmented uncollect).
- `transformation-levels-design.md` — construction steps as
  transformations on the program; program and edit history as one
  structure.
- `commute-design-notes.md` and the three `lazy-stream-*-design.md`
  documents — commuting `List<Option<X>>` → `Option<List<X>>`, which
  led to stream flows: single-pass on-demand evaluation, stream join,
  and commute as a per-close annotation.
- `async-flow-design.md` — the async flow kind: event-loop values,
  parallel threads, racing.
- `incremental-flow-design.md` — the incremental flow kind: state
  variables with dependency-tracked recomputation.
- `types-design.md` and `bundle-provenance-design.md` — validity
  checking without a conventional type system, and preventing invalid
  mixing of sibling case flows.
- `partial-collect-design.md` — partial conditionals settled: the
  partial open dissolves into partial *use* of an ordinary open, the
  old "multiple possible semantics" of partial closes dissolve into
  distinct explicit programs, and what remains is one construct —
  the partial collect (merge some cells of a bundle into a coarser
  flow; the exhaustive collect is its covering instance) with its
  algebra as three short theorems.
- `time-travel-programs-design.md` — sanctioning time-travel
  *authoring*: an under-committed program (sibling opens, deferred
  error flows) whose meaning is its completion into a no-time-travel
  program — derived deterministically (forced, canonical, or honest
  heuristic), shown faint in the editor, overridden by authoring the
  operator you meant, compiled by translation only.
- `first-class-ports-design.md` — the Expr-level port
  representation: per-kind port inventories dissolving Branch and
  the `Joined`/`Filtered` wrappers (into alt ports and binary Join
  nodes), and what that unblocks (barrier constructs,
  well-formedness checks). Also works out the Delay back-edge —
  the write half is its own node, Close-style, with the final
  value as its output.
- `textual-representation-design.md` — a parseable/printable textual
  form for programs. Consistently forward (postfix chains, right
  naming — token order is time); three sorted arrows (`->` value,
  `~>` flow, `-~>` value-with-flow); flows ride the chain implicitly
  (bare `join`/`commute`/`collect` act on the innermost layers, by
  adjacency); graded references — chains, then pronouns (junction
  taps `|`, lane labels, `~` anaphora, all desugared at parse), then
  names, which mark exactly what is shared; `+`-prefixed completion
  lines; spans and derived indentation as the crossing signal.
- `lazy-compile-design.md` — the current runtime-lazy compile
  strategy (implemented).
- `placement-algorithm-notes.md` — the retired compile-time placement
  algorithm and how it could return as an optimisation pass.
- `compile-strategy-design.md` — the planned functional rebuild of
  the compiler: a pipeline of pure passes (derive → check →
  complete → annotate → codegen), downstream facts converted into
  passed-down context, memoisation keyed by (node, context) over
  a context poset, values shared once-per-point across
  divergent-order consumers, and how multi-level programs reach
  JS.
- `product-flows-design.md` — the mutual-constant relationship
  between sibling flows as a construct: the Cross node (flows
  nested asymmetrically but independently — inner shape may not
  depend on outer value), commute-as-transpose made lawful over
  products, partial products vs true raggedness, and the
  point-indexed table it compiles to. Revises the sibling-opens
  completion (Cross replaces Incorporate) and dissolves most of
  the crossed-terminations clash.
- `implementation-strategy.md` — the map from the design record to
  code: five workstreams, a doc-by-doc ledger of what
  implementation must make concrete, and a proposed sequencing.
- `tough-use-cases-design.md` — five real-system programs (an
  HTTP server, a worker pool over hotplugged devices, mergesort,
  a child process with pipes, a websocket protocol) written
  against the existing blocks until they break; the breaks
  ranked into candidate blocks — a concurrency-species dimension
  on collects with lifecycle outputs, the served flow (collect
  as response), bracket, the decision-driven merge family, the
  divide flow (the link transformation, tree-shaped) — plus
  requirements the IO/cancellation rounds inherit.

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
  and flow references (`NodeFlow`, `Joined`, `Filtered`). Sharing is
  opt-in via node identity: bind once in ReScript, reference twice.
  The file's header comment is the reference for how the pieces fit.
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

## Running

```bash
npm install         # one-time
npm run build       # rescript compile
npm start           # node lib/es6/src/Main.res.mjs — runs the test suite
```

`npm run dev` for watch mode.

## Possible next steps

None committed to.

- **First-class ports.** `compileExpr` conflates a node with its
  single value output port; Join and Branch already strain this.
  Design now worked out in `plans/first-class-ports-design.md`
  (pressure inventory, `ValuePort`/`FlowPort` refs, staged
  migration); implementing it would enable compile-time
  well-formedness checks and cleaner case-split flows.
- **Well-formedness checks.** Time-travel detection (`deeper` on
  unrelated scopes) and closed-scope leakage are currently trusted,
  not checked. (Per `plans/time-travel-programs-design.md`, detection
  is also the front half of *completion* — some findings become
  insertions rather than errors.)
- **Partial conditionals.** The spec's `PARTIAL_BRANCH` — open just
  one alt, others propagate "no value". Design now worked out in
  `plans/partial-collect-design.md` (no new open construct needed;
  the new node is the partial collect); implementation lands after
  first-class-ports migration step 2.
- **`Aggregate`/`Disaggregate`** for struct construction and field
  projection.
- **Loop-carried state** — implement one of the two candidates in
  `plans/iteration-with-state-design.md`. The back-edge
  construction both candidates need is worked out in
  `plans/first-class-ports-design.md` ("the write half is a
  node"): the object graph stays a DAG, and the pair supplies the
  previously missing `final` readout.
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
plans/                               design docs (see above)
plans/visual-language-description/   the language description itself
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
