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
- `src/Expr.res` — visual-language expressions. Five node kinds: `Lit`, `App`, `Open`, `Close`, `Join`. Every node is wrapped as `{id: int, kind: kind}`; smart constructors (`lit`, `app`, `open_`, `close_`, `join_`) mint fresh ids from a module-local counter. Currently only the `(Open ListIter, Close ListCollect)` flow combination is implemented.
- `src/Compile.res` — compiles `Expr.expr` to JS. See "Compile architecture" below.
- `src/Main.res` — test runner. Builds Exprs, compiles to IIFE, evals, compares against an expected `JsAst.expr` via `JSON.stringify`. Prints outer-stmt count per test so the effect of sharing/joining is visible.

## Compile architecture (current shape)

`go(ctx, e)` returns `(JsAst.expr, option<scopeRef>)` — the JS expression naming the value, *and* the innermost loop scope it lives in. There is **no global loop stack** and **no per-scope dependency map**: each recursive call hands its caller exactly the placement signal needed for the caller's own binding. This was a deliberate redesign at the user's request — earlier versions had a stack and a dependency pre-pass; both are gone.

`scopeRef = {buffer: array<JsAst.stmt>, depth: int, parent: option<scopeRef>}`:

- `buffer` is the loop body's stmt list (mutated in place during compile).
- `depth` lets `deeper(a, b)` (used in App) be a single int compare instead of a chain walk.
- `parent` is used at close time only — `walkUp(scope, n)` for joined closes.

Per-binding dispatch goes through `bufferOf(ctx, innermost)` — a one-line lookup, no walking.

A pre-pass (`preprocessCloseGroups`) walks the root once and groups every `Close` by the id of its **underlying** Open (after stripping `Join` wrappers). When `go` first hits any Close in a group, `compileGroup` compiles the whole group atomically:

1. Walk the join chain to gather `maxJoinCount + 1` Opens (the underlying plus N outers).
2. Compile the outermost's input.
3. Set up scopes innermost-to-outermost. **Scope reuse**: if an Open is already in the memo (because an enclosing `compileGroup` is mid-compile and put it there), reuse the existing scope instead of creating a duplicate. `createdHere` tracks per-Open which we created vs reused.
4. Allocate one output array per close, at `walkUp(innermost, joinCount + 1)`.
5. Compile each close's value, push at `deeper(innermost, valueScope)`.
6. Clean up only the openers we created in step 3.
7. Emit `for…of`s only for the openers we created in step 3 (reused ones get their `for…of` from the outer compileGroup).

Mixed joinCounts within one group are fine. The only currently-active restriction within a group is that all closes must be `Close ListCollect` and the underlying must be `Open ListIter` — anything else `failwith`s.

**`go` raises on `Open` and `Join`**:

- An `Open`'s element is bound by the surrounding `compileGroup` via the memo, so `go` only reaches an `Open` if the user used it outside any of its Closes (malformed program).
- A `Join` is a *pure flow operation* with **no value output port**. Calling `go` on a `Join` is meaningless and the compiler raises with a message that surfaces the conceptual distinction.

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
- Before declaring something done, run the test suite. The runner currently passes 52 tests; if a change drops that count, something regressed.

## Honoured semantic limitations (currently unenforced)

These are properties of the visual language that the compile *assumes* but doesn't check. Worth flagging if a planned change might rely on them being checked:

- **No time travel.** Combining values from non-nested flows (sibling scopes that aren't on the same nesting chain) is ill-formed but `deeper(a, b)` would silently pick one. Currently fine because we trust input.
- **Closed-scope leakage.** A node bound inside a loop is referenced via the memo as `(EId, Some(closedScope))` even after the loop has been emitted. If a downstream consumer somehow reaches it, we'd emit JS that references an out-of-scope variable. Cheapest detection: `mutable closed: bool` on `scopeRef`, raised by `bufferOf` if asked for a closed buffer.

## Notes

- `rescript.json` controls the compiler: ESM output, emits under `lib/es6/` (`in-source: false`), `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- `lib/` is gitignored; only `.res` sources are tracked.
