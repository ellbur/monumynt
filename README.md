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

Two mutually recursive types: `expr` (value-typed) and `flowRef`
(references to flows). Five node kinds in `expr`:

- **`Lit(JsAst.expr)`** — a literal constant. The payload is any constant
  JS expression (number, string, `Math.PI`, an array or object literal).
- **`App({fn, args})`** — a function application. `fn` is itself a
  `JsAst.expr` (typically an identifier or member access); `args` are
  sub-expressions in this language.
- **`Open({flow, input})`** — opens a flow. Three flow kinds so far:
    - `ListIter` — open a list for element-by-element iteration. One
      value output (the current element) and one flow output.
    - `CaseSplit({alts, discriminator})` — open an alternative-typed
      value for case-by-case dispatch. `discriminator` is a JS function
      `(input) => {tag, value}`. *N* value outputs (reached via
      `Branch`) and one flow output (the dispatch).
    - `OptionIter({discriminator})` — open an option-typed value for
      zero-or-one iteration. `discriminator` is a JS function
      `(input) => value-or-undefined`; the body runs once iff the
      result is not undefined. Compiles to an `if (...)` statement.
- **`Close({branches})`** — closes one or more flows. `branches` is an
  array of `{altName, flow: flowRef, value: expr}`. The kind of close
  is determined by the shape of `branches[0].flow` (after peeling
  Joineds):
    - List close (underlying is `NodeFlow(open_ListIter)`): one
      branch with `altName: None`, `value` the per-iteration push
      expression. Joineds on top lift the output array up that many
      iter levels.
    - Option/iter close (underlying is `NodeFlow(open_OptionIter)`
      or any Joined-mix thereof with `open_ListIter`): one branch
      with `altName: None`, `value` the some-case (or per-iter)
      value. The output form is decided by the walked-up chain: if
      any iter in it is a list, output is `const out = []` with
      `out.push(value)` (a list of one element per chain-firing);
      if the whole chain is options, output is `let out;` with
      `out = value` (a single value, set iff every option fires).
      So List<Option<X>> joined produces a list of just the defined
      values; Option<Option<X>> joined produces a single value set
      iff both fire.
    - Case close (underlying is `NodeFlow(branch_)`): one branch per
      alt with `altName: Some(name)`, `flow` a `NodeFlow` selecting
      that alt's flow port, and the per-alt `value` expression.
    - Filter close (underlying is `Filtered(...)`): one branch with
      `altName: None`, pushes only when the matching alt fires.
      Joineds on top lift the output above N enclosing list levels.
- **`Branch({source: flowRef, alt: string})`** — picks an alt off a
  CaseSplit's flow. Has both a value output port (the per-alt v
  binding, used as a value in App args) and a flow output port (used
  via `NodeFlow(branchExpr)` as a case Close's branch.flow). A Branch
  reached by `go` outside its alt's case-close scope raises.

Three `flowRef` constructors:

- **`NodeFlow(expr)`** — the flow output port of a node. Valid when the
  node has one (Open, Branch). The compiler raises at flow-construction
  time if the node turns out to have no flow output port (Lit, App,
  Close); this is the one well-formedness check the types can't catch
  without GADTs.
- **`Joined(flowRef)`** — wraps an iter flow (ListLoop, OptionLoop,
  another Joined, or a Filtered) and tells the consuming Close to
  lift the output one more iter level. Mixed iter chains are fine
  (List under Option, Option under List, etc.).
- **`Filtered(flowRef)`** — wraps a Branch flow (on a CaseSplit nested
  in a list) and tells the consuming Close to push *inside that alt's
  if-body*. The compile target is a `for…of` containing an `if` that
  pushes only when the filtered alt fires.

What's supported on the flow side:

- **List-iteration**: single/multi Close per Open, nested loops,
  joined closes (stacking Joins gives N-level flatten), mixed joined +
  unjoined closes on one opener.
- **Case-split**: `Open CaseSplit` + a case `Close` over an
  alternative type, exhaustive over the alts. Multi-close on a
  case-split (multiple result variables, one if/else chain). Case-split
  inside a list iter, list iter inside a case branch, nested
  case-splits, shared values across branches — all work via the same
  scope/memo machinery as list flows.
- **Filter** for case-split-in-list: `Filter(Branch(Open CaseSplit))`
  as a list-style Close's flow gives a JS `for…of` containing a
  guarded `if` that pushes only when the filtered alt fires.

Not yet represented: configuration scopes, effect handles, iteration
rails, custom flows, commutes.

### Compile pipeline

`src/Compile.res` translates `Expr.expr` to JavaScript.

- `compileToBody(e)` returns `(array<JsAst.stmt>, JsAst.expr)`: a
  sequence of statements plus a final identifier that names the result.
- `compileToIIFE(e)` wraps the body in `(() => { …; return v_N; })()`
  so the result is a single self-contained JS expression.

Three design ideas drive the compile:

1. **Flows are first-class entities.** A `flowRef` (from Expr.res)
   names a flow — `NodeFlow(e)` refers to a node's flow output port,
   `Joined(inner)` and `Filtered(inner)` are pure structural wrappers.
   `flowFor(ctx, fr: flowRef)` returns the `openFlow` for that ref,
   constructing it lazily on first reference (and memoising by the
   underlying node id for NodeFlow refs). Constructing an Open ListIter
   sets up a loop scope and pushes a placeholder stmt into its parent
   buffer; constructing an Open CaseSplit emits `const split = disc
   (input)` and pushes a placeholder for the if-chain; constructing a
   Branch picks an alt off its source's CaseDispatch and emits a
   `const v = split.value` at the top of that alt's scope (cached per
   `(CaseDispatch, alt)` so distinct Branch nodes share it).

2. **`go(ctx, e: expr)` is the value-port entry point** and returns
   `(JsAst.expr, option<scopeRef>)` — the JS expression *and* the
   innermost loop scope the value lives in. `Open ListIter` returns
   the per-iteration element binding (built or cached via `flowFor`);
   `Branch` returns the per-alt v binding; `Close` calls a consumer
   that attaches lazily to existing flows. `Open CaseSplit` has no
   single value port and `failwith`s (use Branch for per-alt values).

3. **One node = one binding, memoised by id**. A node visited more than
   once compiles to a single binding; subsequent encounters return the
   cached value. Sharing a node = `let`-binding it in ReScript.

Closes are pure consumers, no preprocess pass. `consumeListClose`
walks Joineds to find the innermost loop and join depth; pushes a
`const v_out = []` into the *outermost* loop's `preLoopBuf` (so it
ends up immediately before the for-of at finalisation); compiles the
value; pushes. `consumeCaseClose` flips `demandsExhaustive` on the
shared dispatch, pushes a `let v_close;` into `preDispatchBuf`, and
appends `v_close = value` into each alt's scope. `consumeFilterClose`
walks `inputJoinDepth` ListLoop levels up via the dispatch's recorded
`inputNode`, pushes the output array into that outermost loop's
`preLoopBuf`, and pushes inside the matching alt body. Mixing
filter-close + case-close on the same case-split works naturally —
both attach to the same CaseDispatch; the case-close turns on
exhaustive throw and the filter-close just adds its push to the
matching alt body.

After `go(root)` returns, `finalizeLoops` and `finalizeDispatches`
walk pending entries and use `Array.splice` to replace each
placeholder with `[...preLoopBuf, for-of]` or
`[...preDispatchBuf, if-chain]`. Placeholders are looked up by
reference (`Array.indexOfOpt`), so finalisation order is irrelevant.

Top-level Lit bindings emit into a separate `hoistedLits` buffer
that's prepended to `outerStmts` at the very end. Otherwise a Lit
emitted while a loop is being filled would land in `outerStmts`
after the loop's placeholder, ending up after the for-of (TDZ).

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

**78 tests** cover:

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
- **Filter**: keep only the Justs (doubled), identity filter
  extracting Just values, no-match input giving `[]`,
  positives-only-squared with a sign discriminator, multi-filter
  partition (Justs + Nothings into two output arrays), multi-filter
  same alt (two parallel outputs from one branch), filter under
  joined nested lists (flatten + filter in one chain).
- **Mixing**: filter-close and exhaustive case-close on the same
  case-split (one shared discriminator + if-chain producing both a
  per-iteration scalar via list-close on the outer iter and a
  filtered subset via filter-close).
- **Option flow**: Some(v) doubled, None defaulted; multi-close on
  one option (doubled + tripled in parallel); Option<Option<X>>
  joined (Some only if both fire); Option<List<X>> joined (list
  built only when outer fires); List<Option<X>> joined (list of
  just the defined values — push when defined, skip otherwise).

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
  the other alt(s) propagating "no value" through. With Filter in
  place, this is a related but distinct generalisation.

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
