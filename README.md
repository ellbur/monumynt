# monumynt

An experimental sandbox for a visual flow-based programming language. The
language design is described under [`plans/visual-language-description/`](plans/visual-language-description/);
this repository explores the **non-graphical building blocks** — the data
structures and the compile pipeline that the eventual visual editor would
sit on top of. Layout, rendering, and the diagram-editor side are all out
of scope here.

The code is ReScript 12 compiled to ES modules and run on Node.

## Where things stand

The pipeline goes:

```
visual-language Expr   →   JsAst   →   JavaScript source string
   (built in ReScript)    (typed)        (pretty-printed)
            │                                     │
            └─ Compile.compileToBody / compileToIIFE   └─ eval'd in tests
```

Concretely, the codebase has:

### A typed JavaScript AST and printer

- `src/JsAst.res` — variant types for a useful subset of JS: literals,
  identifiers, member/index access, calls, `new`, arrow & function
  expressions, binary/unary/update/assignment ops, ternary, sequence,
  spread, `await`; statements covering `let`/`const`/`var`, `if`,
  `while`/`do`/`for`/`for…of`/`for…in`, `return`/`break`/`continue`/
  `throw`, `try`/`catch`/`finally`, function declarations, labels; and
  ESM `import` / `export`.

- `src/JsPrint.res` — precedence-aware pretty-printer. Inserts parens
  only when needed, including the tricky cases (`**` right-associativity
  and the unary-on-the-left rule, `??` mixing with `&&`/`||`,
  statement-start ambiguity with `function` and `{`, arrow bodies that
  are object literals). Falls back to bracket notation when a property
  name isn't a valid identifier.

- `src/JsBuild.res` — ergonomic smart constructors so building reads
  like the JS it produces (`call`, `member`, `arrow`, `let_`, `const`,
  `if_`, `forOf`, `ret`, `add`, `eq`, `assign`, `importNamed`, …).

### Expressions for the visual language

`src/Expr.res` defines `expr = {id: int, kind: kind}`, where every node
carries an explicit `id` so that sharing is opt-in via ReScript-level
`let`-binding:

```rescript
let x = lit(int_(7))
let y = app(addFn, [x, x])     // both args are the same node
```

Five node kinds:

- **`Lit(JsAst.expr)`** — a literal constant. The payload is any constant
  JS expression (number, string, `Math.PI`, an array or object literal).
- **`App({fn, args})`** — a function application. `fn` is itself a
  `JsAst.expr` (typically an identifier or member access); `args` are
  sub-expressions in this language.
- **`Open({flow, input})`** — opens a flow. Currently the only
  `openFlow` is `ListIter` — open a list for element-by-element
  iteration. An Open's "value" is the per-iteration current element and
  is only meaningful inside a Close that consumes it.
- **`Close({flow, opener, value})`** — closes a flow. `opener` is an
  opener-shaped node (an `Open` or an `Open` wrapped in any number of
  `Join`s); `value` is the per-iteration expression whose results are
  accumulated. The Close's overall value is the collected list, with
  `N` levels of flattening if its opener is wrapped in `N` `Join`s.
- **`Join({inner})`** — a *pure* flow operation: takes an opener and
  returns an opener. Stacking joins produces deeper flatten on output.
  A `Join` has only a flow output port, no value output port — calling
  the compiler's `go` on a `Join` raises with a clear message.

What's supported on the flow side:

- **Single Open / single Close** — basic list iteration.
- **Single Open / multiple Closes** — many output arrays from one loop.
- **Nested Opens / nested Closes** — list-of-lists in, list-of-lists out.
- **Joined Closes** — `Close(Join(Open(Open(input))), …)` flattens one
  level on output; stacking gives N-level flatten.
- **Mixed joined and unjoined Closes on the same opener** — both kinds
  can coexist, sharing the loops, with each Close getting its own output
  array at its own joined-out scope.

Not yet represented: case splits, configuration scopes, effect handles,
iteration rails, custom flows, commutes.

### Compile pipeline

`src/Compile.res` translates `Expr.expr` to JavaScript.

- `compileToBody(e)` returns `(array<JsAst.stmt>, JsAst.expr)`: a
  sequence of statements plus a final identifier that names the result.
- `compileToIIFE(e)` wraps the body in `(() => { …; return v_N; })()`
  so the result is a single self-contained JS expression.

Two design ideas drive the compile:

1. **`go(ctx, e)` returns `(JsAst.expr, option<scopeRef>)`** — the JS
   expression *and* the innermost loop scope the value lives in. The
   parent of any binding is determined inline from this returned value,
   not by walking a global stack. Lit returns `None`; App returns
   `deeper(args' innermosts)`; an Open's element returns the loop
   scope it was memoised with; a Close returns its output array's
   scope (one or more levels above the loop, depending on join count).

2. **One node = one binding, memoised by id**. A node visited more than
   once compiles to a single binding; subsequent encounters return the
   cached value. Sharing a node = `let`-binding it in ReScript. This
   carries through joined/mixed flows: a per-iteration body shared
   between two Closes computes once and pushes into both output
   arrays.

For list-flow handling, a single pre-pass groups every `Close` by the
id of its underlying `Open` (after stripping any `Join` wrappers).
When `go` first encounters any Close in a group, `compileGroup`
compiles the whole group atomically: walks the join chain to find all
the Opens that need loops, sets up scopes innermost-to-outermost,
allocates each Close's output array at its own `joinCount`-up scope,
compiles each Close's value, and emits the `for…of`s from innermost
to outermost. If the chain walk hits an Open that's already active
(because an enclosing `compileGroup` is mid-compile), the existing
scope is **reused** rather than re-created — this makes mixed-join
groups inside an outer Close work correctly.

### Tests

`src/Main.res` is a small test runner. Each test builds an Expr,
compiles it to an IIFE, evaluates it via `eval`, and compares the
result against an expected `JsAst.expr` (also evaluated) using
`JSON.stringify` for comparison. Each test header reports the number
of outer-level statements emitted, which makes the effect of
sharing/joining visible at a glance.

**52 tests** cover:

- **Value-only fragment**: literals (number, string, bool, array,
  object, member-reference), nested arithmetic, standard-library calls
  (`Math.sqrt`, `Math.max`, `Math.abs`, `Math.pow`, `Array.of`),
  conditional expressions, object construction and field access,
  zero-arg invocation.
- **Sharing**: deliberate non-sharing vs. shared subtrees (diamond,
  triangle, deep diamond, shared `Math.PI`, circle metrics).
- **List-flow basics**: identity map, map of double, empty input,
  element shared inside body, loop-invariant constant hoisted,
  shared value across loop boundary, post-process of map result.
- **Multi-close**: two/three closes from one open, shared per-iter
  intermediate, per-close loop-invariants, two independent loops in
  sequence, one Close used twice downstream.
- **Nested list flows**: nested map producing list-of-lists, with
  empty inner lists, with multi-close on the inner.
- **Joined list flows**: basic join (flatten), identity flatten, empty
  outer, hoisted constant + join, two stacked Joins (3-deep flatten),
  joined and nested side by side.
- **Mixed joined + unjoined on one opener**: outer-close wrapping the
  unjoined while a sibling joined Close pushes flat, with and without
  a shared per-element body.

## Running

```bash
npm install         # one-time
npm run build       # rescript compile
npm start           # node lib/es6/src/Main.res.mjs — runs the test suite
```

`npm run dev` for watch mode.

## Possible next steps

These are the natural directions. None is committed to.

- **Case-split flow.** The next flow kind in the spec —
  `Open CaseSplit` and `Close CaseJoin` over a sum type. The compile
  target is an `if`/`else` (or `switch`), not a loop. Will exercise
  whether the `Open`/`Close`/`Join` machinery generalises across flow
  kinds; "join" on a case-split flow has different semantics from
  "join" on a list flow, and it's worth seeing what the abstractions
  share once both are in.

- **Time-travel check.** Today the compile assumes well-formed input.
  Specifically `deeper(a, b)` quietly picks one when given two
  unrelated scopes (only correct when one is nested in the other), and
  a closed scope can still be referenced via the memo (which would
  produce JS that references an out-of-scope variable). Cheap way to
  detect: `mutable closed: bool` on `scopeRef`, raise if `bufferOf` is
  asked for a closed scope. Worth adding before adding more flow kinds.

- **Make the value/flow port distinction explicit.** Right now `go`
  operates on nodes, conflating the node with its single value output
  port. `Join` has no value port and we surface that with a `failwith`,
  but there's nothing structural preventing a misuse. When case-splits
  arrive (a node with multiple value output ports — one per case), the
  conflation will start to bite for real, and that's the time to model
  ports explicitly.

- **More expression node kinds.** `Aggregate`/`Disaggregate` for struct
  construction and field projection, instead of the current
  one-arrow-function-per-shape pattern. Probably wants a small
  registry of struct types.

- **Iteration rails.** `IterationRail` + `TapIn`/`TapOut`, the
  loop-carried-variable mechanism. Should compile to a single mutable
  `let` register inside the loop (per the iteration-rails design doc).

- **Diagrams as the top-level structure.** The `Diagram` type from the
  spec — value/flow inputs and outputs, named nodes, slots. `Expr`
  would become one piece of what diagrams contain, and the compile
  step would produce a JS function per diagram with proper parameter
  and return wiring.

- **Differential / structural tests.** Today's tests check the
  evaluated JS value. Useful additions: tests that pin the exact
  outer-stmt count for a shape, and golden-file tests for the
  generated JS source (so unintended formatting changes are caught).

- **Pretty-printer polish.** Object-literal shorthand
  (`{x: x}` → `{x}`), template literals, classes — only as needed.

## Layout

```
plans/visual-language-description/   design docs (visual + non-visual)
src/
  JsAst.res                          typed JS AST
  JsPrint.res                        precedence-aware printer
  JsBuild.res                        smart constructors
  Expr.res                           visual-language expressions
  Compile.res                        Expr → JS
  Main.res                           test runner + examples
rescript.json                        ESM output, lib/es6/, .res.mjs suffix
package.json                         "type": "module"
```

`lib/` is gitignored; only `.res` sources are tracked.
