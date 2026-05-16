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

Six node kinds:

- **`Lit(JsAst.expr)`** — a literal constant. The payload is any constant
  JS expression (number, string, `Math.PI`, an array or object literal).
- **`App({fn, args})`** — a function application. `fn` is itself a
  `JsAst.expr` (typically an identifier or member access); `args` are
  sub-expressions in this language.
- **`Open({flow, input})`** — opens a flow. Two flow kinds so far:
    - `ListIter` — open a list for element-by-element iteration. One
      value output (the current element) and one flow output.
    - `CaseSplit({alts, discriminator})` — open an alternative-typed
      value for case-by-case dispatch. `discriminator` is a JS function
      `(input) => {tag, value}`. *N* value outputs and *N* flow outputs
      (one per alt). Specific ports are referenced via `Branch`.
- **`Close({flow, branches})`** — closes a flow. `branches` is an
  array of `{altName, flow, value}`:
    - For `ListCollect`: exactly one branch with `altName: None`.
    - For `CaseJoin`: one branch per alt with `altName: Some(name)`,
      `flow` a `Branch` node selecting that alt's flow port, and the
      per-alt `value` expression.
- **`Join({inner})`** — a *pure* flow operation: wraps a list-iteration
  opener and tells the consuming Close to flatten one level on output.
  Stacking gives more levels. Join has only a flow output port; calling
  `go` on one raises.
- **`Branch({source, alt})`** — picks an output port from a CaseSplit
  Open. The same Branch node serves both roles — value port (used as a
  value in App args, etc.) or flow port (used as a CaseJoin Close's
  branch.flow). Context determines. A Branch reached by `go` outside
  its alt's case-close scope raises.

What's supported on the flow side:

- **List-iteration**: single/multi Close per Open, nested loops,
  joined closes (stacking Joins gives N-level flatten), mixed joined +
  unjoined closes on one opener.
- **Case-split**: `Open CaseSplit` + `Close CaseJoin` over an
  alternative type, exhaustive over the alts. Multi-close on a
  case-split (multiple result variables, one if/else chain). Case-split
  inside a list iter, list iter inside a case branch, nested
  case-splits, shared values across branches — all work via the same
  scope/memo machinery as list flows.

Not yet represented: configuration scopes, effect handles, iteration
rails, custom flows, commutes, joining a case-split flow.

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
prints a human-readable rendering of it, compiles it to an IIFE,
prints the generated JS, evaluates that via `eval`, and compares the
result against an expected `JsAst.expr` (also evaluated) using
`JSON.stringify` for comparison. Each test header reports the number
of outer-level statements emitted, which makes the effect of
sharing/joining visible at a glance.

The Expr rendering (in `src/ExprPrint.res`) is time-forward and flat:
each value the program computes ends up somewhere in the output as a
chain of operations. Single-input ops are joined with `->`; multi-
input ops list their inputs at the start of a line and produce one
new value. Trivially-used literals are inlined; shared sub-
expressions get `#N` labels so the reader can see at a glance what's
being reused. For example:

```
[[1, 2], [3]] -> open (#1) -> open (#2) -> x => x * 2 (#3)
#2, #3 -> close (#4)
#1, #4 -> close (#5)
#2 -> join (#6)
#6, #3 -> close (#7)
#5, #7 -> (a, b) => ({nested: a, flat: b})
```

is the "mixed shared body" test, with `#3` (the doubled element)
visibly shared between the unjoined close (#4) and the joined close
(#7), and the original opens (#1, #2) reused throughout.

**61 tests** cover:

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
- **Case-split**: Maybe-double of Just/Nothing, Either<string,int>
  with different per-branch result types, multi-close on one
  case-split, sign-discriminator that maps raw ints into tagged
  shapes, case-split inside a list iter, shared bonus across branches,
  nested Maybe<Either<…>>.

## Running

```bash
npm install         # one-time
npm run build       # rescript compile
npm start           # node lib/es6/src/Main.res.mjs — runs the test suite
```

`npm run dev` for watch mode.

## Possible next steps

These are the natural directions. None is committed to.

- **Make the value/flow port distinction explicit.** `go` currently
  operates on nodes, conflating the node with its single value output
  port. `Join` has only a flow port, `Branch` is a port-selector but
  carries both ports together — both are surfaced via `failwith`s and
  ad-hoc context. A first-class port concept would let us:
    - eliminate the redundant `const v_b = split.value;` we currently
      emit for Branch nodes whose value port isn't used (only the flow
      port is — e.g. for a Nothing-branch with a literal value);
    - express case-split-flow operations cleanly (e.g. joining a Just
      case across Closes);
    - validate well-formedness at compile time.

- **Time-travel check.** Today the compile assumes well-formed input.
  Specifically `deeper(a, b)` quietly picks one when given two
  unrelated scopes (only correct when one is nested in the other), and
  a closed scope can still be referenced via the memo (which would
  produce JS that references an out-of-scope variable). Cheap way to
  detect: `mutable closed: bool` on `scopeRef`, raise if `bufferOf` is
  asked for a closed scope.

- **Partial conditionals (one-sided case-split).** The spec's
  `PARTIAL_BRANCH` — open just one alt of an alternative type, with
  the other alt(s) propagating "no value" through. This is what filter
  is built out of. With case-split in place, it's a natural extension.

- **Joining case-split flows.** What does it mean to "join" a Just
  flow with the surrounding flow? Not yet implemented — `Join`
  currently only wraps list openers.

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
  ExprPrint.res                      human-readable Expr rendering
  Compile.res                        Expr → JS
  Main.res                           test runner + examples
rescript.json                        ESM output, lib/es6/, .res.mjs suffix
package.json                         "type": "module"
```

`lib/` is gitignored; only `.res` sources are tracked.
