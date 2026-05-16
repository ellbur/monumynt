# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ReScript 12 project compiling to ES modules and running on Node. Source lives in `src/`; the compiler emits `.res.mjs` files under `lib/es6/` (mirroring the `src/` tree).

This is an experimental sandbox for a visual flow-based programming language. Design docs live under `plans/visual-language-description/`. **The graphical / layout side is explicitly out of scope here** — work in this repo is the non-visual building blocks (data structures, compile pipeline). Specifically out of scope: `graph-representation.md`, `visual-layout-guidelines.md`, `rendering-algorithm.md`, `program-to-graph-transformation.md`, and the visual sections of the other docs (2D spread pictures, diagonal wires, vertical-segment custom-flow drawings, etc.).

`README.md` has a fuller status overview and a list of possible next steps; consult it before proposing big additions.

## Commands

- `npm run build` — one-shot compile (`rescript`)
- `npm run dev` — watch mode (`rescript -w`)
- `npm run clean` — remove generated artifacts
- `npm start` — run `node lib/es6/src/Main.res.mjs` (the compiled entry point — currently the test runner)

## Source layout

- `src/JsAst.res` — typed AST for a useful subset of JavaScript (literals, member/index, calls, arrows, function expressions, binary/unary/update/assignment, ternary, sequence, spread, await; statements covering let/const/var, if, while, do, for/for-of/for-in, return/break/continue/throw, try, function decl, label; ESM import/export). No classes, generators, JSX, decorators, template-literal substitutions, or destructuring patterns beyond simple parameters.
- `src/JsPrint.res` — precedence-aware pretty-printer. Handles the tricky cases (`**` right-associativity with no-unary-on-the-left, `??` mixing with `&&`/`||`, statement-start ambiguity with `function` and `{`, arrow bodies that begin with `{`). Falls back to bracket notation for property accesses when the name isn't a valid identifier.
- `src/JsBuild.res` — smart constructors mirroring `JsAst` variants for ergonomic construction. `JsBuild` shadows several short names (`add`, `mul`, etc.) — be aware when `open`ing it.
- `src/Expr.res` — visual-language expressions. Seven node kinds: `Lit`, `App`, `Open`, `Close`, `Join`, `Branch`, `Filter`. Every node is wrapped as `{id: int, kind: kind}`; smart constructors (`lit`, `app`, `open_`, `close_`, `caseClose`, `join_`, `branch_`, `filter_`) mint fresh ids from a module-local counter. Open's `flow` is `ListIter | CaseSplit({alts, discriminator})`. Close has only `branches: array<{altName: option<string>, flow: expr, value: expr}>` — no flow discriminator on the Close itself; the kind is determined by the shape of `branches[0].flow`: a Branch ⇒ case close; a Filter ⇒ filter close (Filter wraps a Branch wrapping a CaseSplit Open whose input is a ListIter); anything else ⇒ list close (peel any Joins). Branch picks one output port from a CaseSplit Open. Filter is the case-split-in-list analogue of Join — wraps a Branch and tells the close to push inside that alt's if-body.
- `src/Compile.res` — compiles `Expr.expr` to JS. See "Compile architecture" below.
- `src/ExprPrint.res` — human-readable rendering of `Expr.expr` for test logs and debugging. Time-forward and flat: each line is a chain of single-input ops separated by `->`, optionally prefixed by a comma-separated source list when the head op has 1+ inputs. Sharing is shown via `#N` labels (renumbered per-render). Trivially-used literals are inlined into their consumer's source list; literals with multiple consumers get a label and their own line.
- `src/Main.res` — test runner. Builds Exprs, prints the Expr rendering, compiles to IIFE, prints the generated JS, evals, compares against an expected `JsAst.expr` via `JSON.stringify`. Prints outer-stmt count per test so the effect of sharing/joining is visible.

## Compile architecture (current shape)

Every flow-producing node — `Open`, `Join`, `Filter`, `Branch` — has a *flow output port*. Flows are first-class entities, constructed lazily and memoised by node id. `flowFor(ctx, e)` returns the `openFlow` for `e`, building it on first reference. `go(ctx, e)` is the value-port entry point.

There is **no preprocess pass**, **no global loop stack**, and **no `closeGroups` / `branchesBySource` maps**. Closes are pure consumers that attach to existing flows lazily.

`scopeRef = {buffer: array<JsAst.stmt>, depth: int, parent: option<scopeRef>}`:

- `buffer` is the loop body's (or alt body's) stmt list, mutated in place; the for-of/if-chain wrappers hold these by reference, so consumers that attach later still appear in the printed output.
- `depth` lets `deeper(a, b)` (used in App) be a single int compare.
- `parent` is used by `walkUp(scope, n)` for joined closes' output placement.

`openFlow = {id: int, kind: openFlowKind}`:

- **`ListLoop`** — built by Open ListIter. Allocates a loop scope; `go(input)` emits the input expression into the loop's parent buffer; pushes a *placeholder* sentinel into the parent buffer (a unique `SBlock([])` whose reference we later find via `Array.indexOfOpt`) where the for-of will be spliced in at finalisation; memoises the per-iteration element binding into `ctx.memo`. Carries a `preLoopBuf` array — bindings consumers want at the loop's parent scope (e.g. output arrays) get pushed here so they end up immediately before the for-of.
- **`CaseDispatch`** — built by Open CaseSplit. Peels any Joins off the input (filter-under-joined-lists), `go(input)` emits the input + `const split = disc(input)`; pushes a placeholder for the if-chain. Carries `altScopes` (one per alt), `preDispatchBuf` (for `let v_close;` decls from case-close consumers), `inputJoinDepth` (so filter consumers know how high to lift), `mutable demandsExhaustive` (set true by case-close), and an `altBranchCache` so distinct Branch nodes for the same (CaseDispatch, alt) share one `v = split.value` binding.
- **`Joined({inner})`** — pure structural wrapper; no emission. List consumers walk through Joineds counting depth.
- **`BranchOf({source, alt, valueName, branchScope})`** — built by Branch. Looks up (or allocates) the per-alt scope on its source CaseDispatch; emits `const v = split.value` at the top of that scope (once per (CaseDispatch, alt), shared across distinct Branch nodes via the cache).
- **`Filtered({inner})`** — pure structural wrapper around a BranchOf. Signals filter semantics to the consuming Close.

**`go(ctx, e)`** dispatches by node kind:

- `Lit` — emits to `ctx.hoistedLits` (a separate buffer prepended to `outerStmts` at the very end). This guarantees top-level Lits are declared before any for-of / if-chain that might use them — under DFS-driven lazy construction, a Lit emitted while a loop is being filled would otherwise land in `outerStmts` after the loop's placeholder, ending up after the for-of (TDZ).
- `App` — same as before; `deeper` over arg scopes; emits a `const v_N = …` into `bufferOf(innermost)`.
- `Open ListIter` — triggers `flowFor`, returns the per-iteration element binding via the memo.
- `Open CaseSplit` — `failwith` (no single value port; reach an alt via Branch).
- `Branch` (value port) — triggers `flowFor`, returns the per-alt `v` binding.
- `Join` / `Filter` — `failwith` (no value port).
- `Close` — calls `consumeClose`, which dispatches by inspecting `flowFor(branches[0].flow).kind`:
    - `BranchOf` → `consumeCaseClose`: validates all branches reference the same dispatch and cover all alts; flips `demandsExhaustive`; pushes `let v_close;` into `preDispatchBuf`; for each branch, compiles the per-alt value into the alt's scope and appends `v_close = value`.
    - `Filtered` → `consumeFilterClose`: walks `inputJoinDepth` ListLoop levels up to find the outermost loop, pushes `const v_out = []` into its `preLoopBuf`, compiles the value into the alt's scope, pushes.
    - `ListLoop` / `Joined` → `consumeListClose`: walks Joineds to count joinDepth, walks `joinDepth` Open.input levels up to find the outermost loop, pushes `const v_out = []` into its `preLoopBuf`, compiles the value, pushes at the deeper of innermost loop scope and value scope.

**Mixing is uniform**: case-close + filter-close on the same case-split share one CaseDispatch, one if-chain, one `const split = …`. The case-close turns on `demandsExhaustive` (so the if-chain ends with `else throw`); the filter-close just adds its push to the matching alt body. Tested.

**Finalisation.** After `go(root)` returns, `finalizeLoops` and `finalizeDispatches` walk `pendingLoops` / `pendingDispatches`, look each placeholder up by reference (`Array.indexOfOpt`), and `Array.splice` it out for `[...preLoopBuf, for-of]` (loops) or `[...preDispatchBuf, if-chain]` (dispatches). Order of finalisation doesn't matter — splices elsewhere only move the placeholder's *index*, not its identity. For dispatches: alts whose body is empty are omitted unless `demandsExhaustive`, and the chain ends with `else throw …` only if `demandsExhaustive`.

## Conventions

- **Sharing is opt-in via ReScript-level binding.** Two calls to `Expr.lit(int_(5))` produce two distinct nodes (different ids, no sharing). To share, bind once and reuse: `let x = lit(int_(5)); app(f, [x, x])`.
- **One node = one binding** in the compiled JS, including `Lit`s. A shared `Lit` whose payload is non-trivial (e.g. `Math.PI`) thus evaluates exactly once. Trivial literals like `5` also get bound — this is uniform and worth the noise.
- **Value port vs flow port** is conceptually distinct, but `go` operates on whole nodes — i.e. it conflates the node with its single value output port. This works for Lit/App/Open (all have a single value output port) and is currently surfaced as `failwith` for Join (which has none). When case-splits arrive (one node, multiple value output ports per case), this conflation will need to be addressed properly.
- **Side-effect-during-recursion-with-`||` hazard**: `acc || computeDeps(a)` will skip the right operand once the left is `true`, dropping any side effect (e.g. populating a map). Bind into a `let` first, then OR the values: `let r = computeDeps(a); acc || r`. This bit us once — keep an eye on similar shapes.
- **ReScript Warning 30** ("label X is defined in both types Y and Z") fires when two top-level record types share a field name. Field names on inline records inside variants are scoped and don't conflict. Keep top-level record field names distinct (e.g. `importSpecifier` uses `imported`/`local`; `exportSpecifier` uses `exported`/`as_`).
- **Inline-record-in-variant punning gotcha**: `Join({inner})` (field punning shorthand) sometimes fails to compile with "this use of an inlined record is not allowed: its anonymous type would escape its constructor scope." The fix is to spell it out: `Join({inner: inner})`. We hit this on `join_`'s smart constructor.

## ReScript stdlib lookups

ReScript 12 includes its standard library bundled (no separate `@rescript/core` install). The signatures (`.resi` files) are at `node_modules/@rescript/runtime/lib/ocaml/Stdlib_*.resi`. Useful ones:

- `Stdlib_Array.resi` — `Array.map`, `Array.reduce(arr, init, fn)`, `Array.join(arr, sep)` (strings only; `joinUnsafe` for non-strings), `Array.flat`, `Array.push` (mutating), `Array.pop` (returns option), `Array.forEach`, `Array.forEachWithIndex`, `Array.getUnsafe`.
- `Stdlib_String.resi` — `String.repeat(s, n)`, `String.charAt(s, i)`, `String.length`, `String.split`.
- `Stdlib_Float.resi` — `Float.isNaN`, `Float.isFinite`, `Float.toString`.
- `Stdlib_Map.resi` — JS-Map binding: `Map.make`, `Map.get` (returns option), `Map.set`, `Map.has`, `Map.delete`. Generic over key type; works fine with int keys.
- `failwith` is in `Pervasives` (auto-opened); `Pervasives.res` lives next to the others.

When unsure of an API, grep these `.resi` files rather than guessing.

## Testing approach

In `Main.res`, the runner uses two FFI bindings:

```rescript
@val external evalJs: string => 'a = "eval"
@val external jsonStringify: 'a => string = "JSON.stringify"
```

It wraps the input to `eval` in `(…)` so that expressions starting with `{` (object literals) aren't reinterpreted as blocks. Comparison is via `JSON.stringify` on both sides — robust for numbers, strings, booleans, arrays, plain objects. Doesn't roundtrip functions / `undefined` / `NaN`/`Infinity`, so don't put those in expected values.

Tests are inline in `Main.res`. Each test prints the generated JS, the result, and a header with the outer-stmt count. The count is informative — e.g. a "shared" version of an expression should produce fewer outer stmts than an "unshared" version.

## Working with the user

The user designs incrementally and likes to think out loud about a step before any code is written. Rough pattern from past sessions:

- They share an intuition or partial design and invite engagement, *not* immediate implementation. ("It seems X. Does that work?" usually means "talk it through first.")
- They prefer "baby steps" — one small, well-understood addition at a time. Don't bring in extra design dimensions ("multi-close at the same time as nested at the same time as join") in one round.
- They have strong design taste — when they say something like "we don't need to walk the stack" or "join is a pure flow operation," it's worth taking literally and working out the implications, not paraphrasing or smoothing over.
- When you see a non-obvious design tradeoff, surface it and let them choose. Multiple options laid out concretely > one chosen for them.
- Before declaring something done, run the test suite. The runner currently passes 69 tests; if a change drops that count, something regressed.

## Honoured semantic limitations (currently unenforced)

These are properties of the visual language that the compile *assumes* but doesn't check. Worth flagging if a planned change might rely on them being checked:

- **No time travel.** Combining values from non-nested flows (sibling scopes that aren't on the same nesting chain) is ill-formed but `deeper(a, b)` would silently pick one. Currently fine because we trust input.
- **Closed-scope leakage.** A node bound inside a loop is referenced via the memo as `(EId, Some(closedScope))` even after the loop has been emitted. If a downstream consumer somehow reaches it, we'd emit JS that references an out-of-scope variable. Cheapest detection: `mutable closed: bool` on `scopeRef`, raised by `bufferOf` if asked for a closed buffer.

## Notes

- `rescript.json` controls the compiler: ESM output, emits under `lib/es6/` (`in-source: false`), `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- `lib/` is gitignored; only `.res` sources are tracked.
