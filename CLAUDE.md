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
- `src/Expr.res` — visual-language expressions. Currently just `Lit(JsAst.expr)` and `App({fn: JsAst.expr, args: array<expr>})`. Every node is wrapped as `{id: int, kind: kind}`; smart constructors `lit` and `app` mint fresh ids from a module-local counter.
- `src/Compile.res` — compiles `Expr.expr` to JS. Memoizes on node id via `Map.t<int, JsAst.expr>`; every node emits exactly one `const v_N = …;` binding on first visit, and reused nodes return the cached identifier on subsequent visits. `compileToBody` returns `(stmts, finalExpr)`; `compileToIIFE` wraps in `(() => { …; return v; })()`.
- `src/Main.res` — test runner. Builds Exprs, compiles to IIFE, evals, compares against an expected `JsAst.expr` via `JSON.stringify`. Prints binding count per test so sharing is visible.

## Conventions

- **Sharing is opt-in via ReScript-level binding.** Two calls to `Expr.lit(int_(5))` produce two distinct nodes (different ids, no sharing). To share, bind once and reuse: `let x = lit(int_(5)); app(f, [x, x])`. This is the explicit-identity contract.
- **Every Expr node = one `const` binding** in the compiled JS, including `Lit`s. Chosen so that a shared `Lit` whose payload is non-trivial (e.g. `Math.PI`, or any JS expression with potential side effects) evaluates exactly once. The cosmetic cost is that trivial literals like `5` also get bound.
- **ReScript Warning 30** ("label X is defined in both types Y and Z") fires when two top-level record types share a field name. Field names on inline records inside variants are scoped and don't conflict. Keep top-level record field names distinct (e.g. `importSpecifier` uses `imported`/`local`; `exportSpecifier` uses `exported`/`as_` to avoid the clash).

## ReScript stdlib lookups

ReScript 12 includes its standard library bundled (no separate `@rescript/core` install). The signatures (`.resi` files) are at `node_modules/@rescript/runtime/lib/ocaml/Stdlib_*.resi`. Useful ones:

- `Stdlib_Array.resi` — `Array.map`, `Array.reduce(arr, init, fn)`, `Array.join(arr, sep)` (strings only; `joinUnsafe` for non-strings), `Array.flat`, `Array.push` (mutating), `Array.forEach`.
- `Stdlib_String.resi` — `String.repeat(s, n)`, `String.charAt(s, i)`, `String.length`, `String.split`.
- `Stdlib_Float.resi` — `Float.isNaN`, `Float.isFinite`, `Float.toString`.
- `Stdlib_Map.resi` — JS-Map binding: `Map.make`, `Map.get` (returns option), `Map.set`, `Map.has`, `Map.delete`. Generic over key type; works fine with int keys.

When unsure of an API, grep these `.resi` files rather than guessing.

## Testing approach

In `Main.res`, the runner uses two FFI bindings:

```rescript
@val external evalJs: string => 'a = "eval"
@val external jsonStringify: 'a => string = "JSON.stringify"
```

It wraps the input to `eval` in `(…)` so that expressions starting with `{` (object literals) aren't reinterpreted as blocks. Comparison is via `JSON.stringify` on both sides — robust for numbers, strings, booleans, arrays, plain objects. Doesn't roundtrip functions / `undefined` / `NaN`/`Infinity`, so don't put those in expected values.

## Notes

- `rescript.json` controls the compiler: ESM output, emits under `lib/es6/` (`in-source: false`), `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- `lib/` is gitignored; only `.res` sources are tracked.
- The plans directory contains documents the user described as having "visual" and "non-visual" parts. The non-visual building blocks are what we model; the visual parts (graph layout, rendering, the editor) are out of scope.
