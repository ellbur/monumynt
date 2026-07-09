# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ReScript 12 project compiling to ES modules and running on Node. Source lives in `src/`; the compiler emits `.res.mjs` files under `lib/es6/` (mirroring the `src/` tree).

This is an experimental sandbox for a visual flow-based programming language. Design docs live under `plans/` (design explorations, most far ahead of the code); `plans/README.md` is the index with reading order and per-document status. Rejected/dissolved ideas are recorded in place in the doc that owns the topic, short and reason-focused — check the relevant doc's rejection notes before proposing a construct, and check the index's commonly-misread-statuses note before treating something as rejected. **The graphical / layout side is explicitly out of scope here** — work in this repo is the non-visual building blocks (data structures, compile pipeline). Specifically out of scope: `plans/graph-representation.md`, `plans/visual-layout-guidelines.md`, `plans/rendering-algorithm.md`, `plans/program-to-graph-transformation.md`, and visual sections of the other docs (vertical-segment custom-flow drawings, rail drawings, etc.).

`README.md` (root) has the project overview and possible next steps; consult it and `plans/README.md` before proposing big additions.

## Commands

- `npm run build` — one-shot compile (`rescript`)
- `npm run dev` — watch mode (`rescript -w`)
- `npm run clean` — remove generated artifacts
- `npm start` — run `node lib/es6/src/Main.res.mjs` (the compiled entry point — currently the test runner)

## Source layout

- `src/JsAst.res` — typed AST for a useful subset of JavaScript (literals, member/index, calls, arrows, function expressions, binary/unary/update/assignment, ternary, sequence, spread, await; statements covering let/const/var, if, while, do, for/for-of/for-in, return/break/continue/throw, try, function decl, label; ESM import/export). No classes, generators, JSX, decorators, template-literal substitutions, or destructuring patterns beyond simple parameters.
- `src/JsPrint.res` — precedence-aware pretty-printer. Handles the tricky cases (`**` right-associativity with no-unary-on-the-left, `??` mixing with `&&`/`||`, statement-start ambiguity with `function` and `{`, arrow bodies that begin with `{`). Falls back to bracket notation for property accesses when the name isn't a valid identifier.
- `src/JsBuild.res` — smart constructors mirroring `JsAst` variants for ergonomic construction. `JsBuild` shadows several short names (`add`, `mul`, etc.) — be aware when `open`ing it.
- `src/Expr.res` — visual-language expressions. Two mutually recursive types: `expr` (value-typed nodes) and `flowRef` (references to flows). Five node kinds in `expr`: `Lit`, `App`, `Open`, `Close`, `Branch`. Each wrapped as `{id: int, kind: kind}`; smart constructors (`lit`, `app`, `open_`, `close_`, `caseClose`, `branch_`) mint fresh ids. Three `flowRef` constructors: `NodeFlow(expr)` (the flow output port of a node — Open, Branch — useable when that node has one), `Joined(flowRef)`, `Filtered(flowRef)`. The flow-only ops `join_` and `filter_` take and return flowRef. Open's `flow` is `ListIter | CaseSplit({alts, discriminator}) | OptionIter` (OptionIter's input is itself the option: `undefined` means None; convert other encodings upstream via App). Close has `branches: array<{altName: option<string>, flow: flowRef, value: expr}>`; the kind is determined by the shape of `branches[0].flow` after peeling Joineds: a NodeFlow(branch) ⇒ case close; a Filtered ⇒ filter close; a NodeFlow(open ListIter) ⇒ list close; a NodeFlow(open OptionIter) ⇒ option close. Branch picks one output port from a CaseSplit Open. The `flowRef` type catches misuse syntactically (you can't try to App a flow, nor branch off a Lit).
- `src/Compile.res` — compiles `Expr.expr` to JS. See "Compile architecture" below.
- `src/ExprPrint.res` — human-readable rendering of `Expr.expr` for test logs and debugging. Time-forward and flat: each line is a chain of single-input ops separated by `->`, optionally prefixed by a comma-separated source list when the head op has 1+ inputs. Sharing is shown via `#N` labels (renumbered per-render). Trivially-used literals are inlined into their consumer's source list; literals with multiple consumers get a label and their own line.
- `src/Main.res` — test runner. Builds Exprs, prints the Expr rendering, compiles to IIFE, prints the generated JS, evals, compares against an expected `JsAst.expr` via `JSON.stringify`. Prints outer-stmt count per test so the effect of sharing/joining is visible.

## Compile architecture (current shape)

Every Expr node compiles to a `lazy` JS binding; every reference forces. The compiler decides almost nothing about placement — each binding goes at `deeper(args' bodies)` (eager), and runtime laziness handles "compute only when needed" and "compute only once" automatically.

Runtime helpers emitted at the top of each IIFE:

```js
const __lazy__ = (t) => ({v: undefined, t, c: false});
const __lazyDone__ = (v) => ({v, t: null, c: true});
const __force__ = (z) => {
  if (!z.c) { z.v = z.t(); z.t = null; z.c = true; }
  return z.v;
};
```

The previous compile (through commit `750b14c`) did compile-time consumer-driven placement with a loopDepth-bounded sink pass, building loop/dispatch skeletons eagerly and splicing consumers in at a finalisation step. All of that is gone — **no preprocess pass, no placeholders, no finalisation, no scope splicing**; see `plans/placement-algorithm-notes.md` for that design and how it could be revived as an optimisation pass, and `plans/lazy-compile-design.md` for the rationale behind the current strategy. Closes are pure consumers: each compiles to one self-contained lazy whose thunk holds the entire iteration logic (for-of / if / if-chain / nested combinations).

Key pieces:

- `bodyRef = {buffer: array<JsAst.stmt>, depth: int, parent: option<bodyRef>}` — a statement buffer inside some thunk under construction (a for-of body, an if body, an alt body). Passed around as `option<bodyRef>`, `None` meaning `ctx.outerStmts`. `depth` makes `deeper(a, b)` a single int compare; `parent` supports `isAncestor`.
- `ctx.memo: Map<int, array<(option<bodyRef>, string)>>` — per Expr id, the bindings already emitted and the body each lives in.
- `compileExpr(ctx, e, currentBody)` returns a name. `lookupMemo` scans the id's entries for one whose body `isAncestor` of `currentBody` and reuses it; otherwise it emits fresh. The ancestor check is what stops a binding that lives inside one thunk from being referenced out of another.

`compileExpr` dispatches by node kind:

- `Lit` — `const v = __lazyDone__(payload)` pushed to `outerStmts`, memoised at `None`, so it's shared by every consumer everywhere.
- `App` — compiles args first, takes `deeper` over the args' bodies, emits `const v = __lazy__(() => fn(__force__(a1), …))` there.
- `Open` or `Branch` reached as a value — `failwith`. Their value ports (per-iter element, per-alt payload) exist only inside a consuming Close's thunk, where the Close pre-memoises them before compiling the value subtree.
- `Close` — dispatches on the shape of `branches[0].flow` after peeling Joineds:
    - `NodeFlow(Open ListIter | OptionIter)` → `emitIterClose`: walks the opener chain `joinDepth` levels up (`walkOpenerChain`), classifies each level as list or option, and builds one thunk of nested for-of / if statements. Each level's element binding (`const v_elem = __lazyDone__(…)`) is memoised into that level's `bodyRef`. Output form follows the **"any list in chain → list" rule**: any list level ⇒ `const out = []` + push per chain-firing; all options ⇒ `let out;` + assign (set iff every option fires).
    - `NodeFlow(Branch)` → `emitCaseClose`: validates exactly one branch per alt (exhaustive); thunk is `const split = disc(force(input)); let out;` plus an if-chain on `split.tag` ending in `else throw`. Per alt, one shared `const v = __lazyDone__(split.value)` binding — `collectBranchesByAlt` pre-memoises every Branch node for that (case-split, alt) to it before the alt's value compiles.
    - `Filtered` → `emitFilterClose`: requires the case-split's input to be an `Open ListIter`; thunk is accumulator + nested for-ofs (joinDepth lifts across ancestor list iters) + per-element dispatch + `if (split.tag === alt) { …push }`.

Multi-close on one opener = one lazy per close, each thunk iterating independently with its own loop/dispatch. So mixing case-close + filter-close on one case-split just works — independent thunks; the case one is exhaustive with `else throw`, the filter one pushes in its alt — but the discriminator runs once per consuming thunk, not once total. Tested.

Entry points: `compileToBody(e)` returns `(stmts, forceOf(root))` with the runtime helpers prepended to the emitted statements; `compileToIIFE(e)` wraps that in `(() => { …; return …; })()`.

## Conventions

- **Sharing is opt-in via ReScript-level binding.** Two calls to `Expr.lit(int_(5))` produce two distinct nodes (different ids, no sharing). To share, bind once and reuse: `let x = lit(int_(5)); app(f, [x, x])`.
- **One node = one binding per accessible scope**, including `Lit`s. A shared `Lit` whose payload is non-trivial (e.g. `Math.PI`) evaluates exactly once (Lits are memoised at the top level). Trivial literals like `5` also get bound — this is uniform and worth the noise. The caveat: a node that depends on a per-iteration value re-emits inside each consuming close's thunk, so sharing across sibling closes' loops is not preserved (see `plans/lazy-compile-design.md`).
- **Value port vs flow port** is conceptually distinct, but `compileExpr` operates on whole nodes — it conflates the node with its single value output port. This works for Lit/App/Close; Open and Branch (whose value ports only exist inside a consuming Close's thunk) are surfaced as `failwith` when reached as a value outside one. First-class ports remain a possible next step (design worked out in `plans/first-class-ports-design.md`; see README).
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

## Language design philosophy

Six principles run through the language design; the full statements,
with the design conversations that earned each one, live in
`plans/language-design-philosophy.md`. Read that before evaluating any
new primitive or construct. In one line each:

- **Example first, then generalise.** Write the concrete case, then
  identify what makes it general — never declare structure upfront.
- **Inside-out / cases as values.** No construct makes an expression's
  interior scope differ from its exterior; cases are values you flow
  through, not scopes; no magic names.
- **Foundations before features.** Critiquing and rejecting candidates
  on paper is cheaper than implementing the wrong primitive.
- **Building blocks at the programmer's abstraction level.** Not
  minimal primitives; one obvious *reading* per program, however many
  authoring paths converge to it.
- **No bottlenecks — neither product nor sum.** Wires pass through
  combining constructs as themselves: no tuple packed just to pass a
  join (product), no tagged union packed just to pass a race (sum);
  joins and races are barriers with corresponding inputs and outputs.
- **Abstraction is the source of truth; concreteness is a derived
  view.** Lowerings are read-only derived views you reference, never
  the thing you edit; derivation is free and downward, abstraction
  earned and upward.

Alongside the principles there is a **standing method — sample
reality** (adopted 2026-07-09; statement and rules in
`plans/language-design-philosophy.md`, first run in
`plans/real-loop-survey.md`): when a construct's importance is
assumed rather than measured, an inventory needs ranking, or a rule
needs contact evidence, draw a seeded random sample of real code
(corpora installed on this machine work fine), classify it against
the current and candidate vocabulary, and let the frequencies
reweight the agenda. Seeded and documented protocol, no filtering
for interesting, biases stated with their direction, evidence kept
separate from decision. Use it frequently — reach for it proactively
when design discussion is running ahead of evidence.

## Working with the user

The user designs incrementally and likes to think out loud about a step before any code is written. Rough pattern from past sessions:

- They share an intuition or partial design and invite engagement, *not* immediate implementation. ("It seems X. Does that work?" usually means "talk it through first.")
- They prefer "baby steps" — one small, well-understood addition at a time. Don't bring in extra design dimensions ("multi-close at the same time as nested at the same time as join") in one round.
- They have strong design taste — when they say something like "we don't need to walk the stack" or "join is a pure flow operation," it's worth taking literally and working out the implications, not paraphrasing or smoothing over.
- When you see a non-obvious design tradeoff, surface it and let them choose. Multiple options laid out concretely > one chosen for them.
- Before declaring something done, run the test suite. The runner currently passes 80 tests; if a change drops that count, something regressed.

## Honoured semantic limitations (currently unenforced)

These are properties of the visual language that the compile *assumes* but doesn't check. Worth flagging if a planned change might rely on them being checked:

- **No time travel.** Combining values from non-nested flows (sibling bodies that aren't on the same nesting chain) is ill-formed but `deeper(a, b)` would silently pick one. Currently fine because we trust input.
- **Closed-scope leakage** used to be on this list (referencing a binding emitted inside an already-built thunk from outside it, producing JS with an out-of-scope variable). It's now structurally guarded: `lookupMemo` only reuses a binding whose body is an ancestor of the requesting body, and an Open/Branch reached as a value outside its consuming Close `failwith`s. Kept as a note in case a future change bypasses the memo.

## Notes

- `rescript.json` controls the compiler: ESM output, emits under `lib/es6/` (`in-source: false`), `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- `lib/` is gitignored; only `.res` sources are tracked.
