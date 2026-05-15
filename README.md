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
visual-language Expr          →   JsAst   →   JavaScript source string
   (built in ReScript)        (typed)        (pretty-printed)
            │                                         │
            └─── Compile.compileToBody / compileToIIFE         └── eval'd in tests
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

### A minimal expression representation for the visual language

- `src/Expr.res` — for now, just two node kinds: `Lit(JsAst.expr)` for a
  literal constant (any constant JS expression — number, string,
  `Math.PI`, an array or object literal) and `App({fn, args})` for a
  function application (where `fn` is itself a `JsAst.expr`, typically
  an identifier or member access). **Every node carries an explicit
  `id`**; smart constructors auto-mint fresh ids so sharing is opt-in
  via ReScript-level `let`-binding:

  ```rescript
  let x = lit(int_(7))
  let y = app(addFn, [x, x])     // both args are the same node
  ```

- Flows, case splits, iteration, configuration scopes, and effect
  handles from the design docs are **not yet represented**.

### Compile pipeline

- `src/Compile.res` —

  - `compileToBody(e)` returns `(array<JsAst.stmt>, JsAst.expr)`: a
    sequence of `const v_N = …;` statements plus a final identifier that
    names the result.

  - `compileToIIFE(e)` wraps the body in `(() => { …; return v_N; })()`
    so the result is a single self-contained JS expression.

  - **One node = one binding.** The compiler keeps a `Map<int,
    JsAst.expr>` keyed by node id; a node visited more than once emits a
    binding only on first encounter and reuses the variable thereafter.
    A shared sub-expression therefore evaluates exactly once in the
    generated JS, no matter how many parents consume it.

### Tests

- `src/Main.res` is a small test runner. Each test builds an Expr,
  compiles it to an IIFE, evaluates it via `eval`, and compares the
  result against an expected `JsAst.expr` (also evaluated) using
  `JSON.stringify` for comparison. The header for each test reports the
  number of `const` bindings the compiler emitted, which makes the
  effect of sharing visible — for example:

  ```
  --- unshared: (2*3) + (2*3) — two independent sub-trees  (7 bindings) ---
  --- shared:   (2*3) + (2*3) — single 2*3 bound and reused  (4 bindings) ---
  ```

- 28 examples cover literals (number, string, bool, array, object,
  member-reference), nested arithmetic, standard-library calls
  (`Math.sqrt`, `Math.max`, `Math.abs`, `Math.pow`, `Array.of`),
  conditional expressions via inline arrow functions, object
  construction and field access, zero-arg invocation, deliberate
  non-sharing, and several sharing patterns (diamond, triangle, deep
  diamond, shared `Math.PI`, and a circle-metrics example with two
  shared inputs).

## Running

```bash
npm install         # one-time
npm run build       # rescript compile
npm start           # node lib/es6/src/Main.res.mjs — runs the test suite
```

`npm run dev` for watch mode.

## Possible next steps

These are the natural directions, roughly in order of how foundational
they are. None is committed to.

- **Flows.** The headline missing piece. Add `Uncollect`/`Collect` (with
  the `Iteration` / `CaseSplit` / `ConfigScope` variants from the
  spec), `Bundle`/`Unbundle`, `Join`, `Commute`, `Incorporate`. Flow
  identity wires need their own representation alongside value wires.
  Once that's in, tests can demonstrate things like list-iteration
  programs compiling to ordinary JS `for` loops.

- **More expression node kinds.** `Aggregate`/`Disaggregate` for struct
  construction and field projection (vs. the current
  one-arrow-function-per-shape pattern). Probably wants a small
  registry of struct types.

- **Iteration rails.** `IterationRail` + `TapIn`/`TapOut`, the
  loop-carried-variable mechanism. Should compile to a single mutable
  `let` register (per the iteration-rails design doc).

- **Diagrams as the top-level structure.** The `Diagram` type from the
  spec — value/flow inputs and outputs, named nodes, slots. `Expr`
  would become one piece of what diagrams contain, and the compile
  step would produce a JS function per diagram with proper parameter
  and return wiring.

- **Validation.** Structural checks: well-formed sources, flow
  alignment, bundle closure, no-time-travel, rail discipline. These
  are described semantically in the design docs but not yet enforced
  anywhere in code.

- **Differential / structural tests.** Today's tests check the
  evaluated JS value. Useful additions: tests that pin the exact
  binding count for a shape, and golden-file tests for the generated
  JS source (so unintended formatting changes are caught).

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
