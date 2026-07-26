# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ReScript 12 project compiling to ES modules and running on Node. Source lives in `src/`; the compiler emits `.res.mjs` files under `lib/es6/` (mirroring the `src/` tree).

This is an experimental sandbox for a visual flow-based programming language. Design docs live under `plans/` (design explorations, most far ahead of the code); `plans/README.md` is the index with reading order and per-document status. Rejected/dissolved ideas are recorded in place in the doc that owns the topic, short and reason-focused — check the relevant doc's rejection notes before proposing a construct, and its status header before treating something as rejected (deferred optimisations and unpicked candidates are not rejections). **The graphical / layout side is explicitly out of scope here** — work in this repo is the non-visual building blocks (data structures, compile pipeline). Specifically out of scope: `plans/graph-representation.md`, `plans/visual-layout-guidelines.md`, `plans/rendering-algorithm.md`, `plans/program-to-graph-transformation.md`, and visual sections of the other docs (vertical-segment custom-flow drawings, rail drawings, etc.).

`README.md` (root) has the project overview and possible next steps; consult it and `plans/README.md` before proposing big additions.

## Commands

- `npm run build` — one-shot compile (`rescript`)
- `npm run dev` — watch mode (`rescript -w`)
- `npm run clean` — remove generated artifacts
- `npm start` — run `node lib/es6/src/Main.res.mjs` (the compiled entry point — currently the test runner)

## Source layout

- `src/JsAst.res` — typed AST for a useful subset of JavaScript (literals, member/index, calls, arrows, function expressions, binary/unary/update/assignment, ternary, sequence, spread, await; statements covering let/const/var, if, while, do, for/for-of/for-in, return/break/continue/throw, try, function decl, label; ESM import/export; `ERaw` — a verbatim-JS escape hatch for the textual form's `js "…"` externs, printed parenthesized). No classes, generators, JSX, decorators, template-literal substitutions, or destructuring patterns beyond simple parameters.
- `src/JsPrint.res` — precedence-aware pretty-printer. Handles the tricky cases (`**` right-associativity with no-unary-on-the-left, `??` mixing with `&&`/`||`, statement-start ambiguity with `function` and `{`, arrow bodies that begin with `{`). Falls back to bracket notation for property accesses when the name isn't a valid identifier.
- `src/JsBuild.res` — smart constructors mirroring `JsAst` variants for ergonomic construction. `JsBuild` shadows several short names (`add`, `mul`, etc.) — be aware when `open`ing it.
- `src/Program.res` — **the program of record**: the ports-first representation. A program is a **node set + distinguished outputs** (no root expression). Node kinds: `Lit`, `App({fn, args})`, `Uncollect({flowKind, input, nesting})` (flowKind `List` / `Option` / `Stream` / `Case({alts, discriminator})` — the opener; `Stream` is the pulled-on-demand axis, structurally identical to `List`), `Collect({branches})` (the consumer — coverage read off the branches: iter, full case, partial case), binary `Join({outer, inner})`, `Commute`, `Cross({left, right})`, and the `DelayRead`/`DelayWrite` register pair. Ports are named strings: value refs are `ValuePort(node, port)`, flow refs `FlowPort(node, port)`; a Case uncollect has one `<alt>` value port and one `<alt>` flow port per alt (per-alt ports, no Branch node). Canonical `dump`/`equal`.
- `src/Build.res` — typed handles over `Program` ("strings below, typed handles above"): smart constructors return records of pre-built refs so authoring never spells a port string. The builder also *collects the node set* (that is how root-unreachable register write-halves stay in the program); `finish(b, ~outputs)` closes it. Sharing is opt-in: bind a handle once and reuse its refs.
- `src/Context.res` / `src/Poset.res` — flow-context: the ordered path of flows open on a consumer chain (bundle-provenance), with `Poset.res` the series-parallel generalisation (nesting = SERIES, Cross = PARALLEL) providing `≤` and the product `merge`. Shared by Check, Codegen, and TextResolve.
- The compile pipeline as pure passes (`plans/compile-strategy-design.md`): `Derive.res` (0, v0 identity) → `Complete.res` (2, inserts a Cross for a sibling-opens combine) → `Check.res` (1, witnesses: alignment / join-adjacency / invariance / flow-borne / coverage) → `Annotate.res` (3, write index, species, flow-variable sets) → `Codegen.res` (4). `Pipeline.res` orchestrates and returns witnesses as data. **See `src/ARCHITECTURE.md` first** — it records module status, decisions, and the worklist.
- `src/Codegen.res` — the code generator: pure let-floating placement, a `(node, port, context)` memo with prefix reuse, thunk-tagged contexts. Emitters cover the value fragment, iter/case/filter/partial collects, registers, the whole-table Cross at any rank, and the stream collect (a `zipStream` fold over `Delayed` cells — `emitIterCollect` with the loop taken out); the emitters that still raise `Codegen.Todo` are genuine gaps owned by the poset round and by the stream round's steps 3/6. `Runtime.res` is the emitted prelude, layered: three lazy helpers for the eager fragment, plus the `Delayed`-cell stream runtime when a program uses a stream flow.
- `src/Text*.res` — the textual surface (`textual-representation-design.md`): `TextLex` (line-oriented lexer) → `TextParse` → `TextAst` → `TextResolve` (names, taps, implicit flow stack → `Build`), and `TextPrint` (`Program` → text, fused postfix chains).
- `src/Main.res` — the smoke suite / playground (`npm start`). Text and handles building identical wiring, eval'd results validated against author-written expected `JsAst.expr` values, and round-trips through the text surface.

## Compile architecture (current shape)

Every node compiles to a `lazy` JS binding; every reference forces. The compiler decides almost nothing about placement — bindings float to the outermost context that contains all their uses, and runtime laziness handles "compute only when needed" and "compute only once" automatically. **`src/ARCHITECTURE.md` is the deep record**; this is the summary.

Runtime helpers (emitted per output, from `Runtime.res`):

```js
const __lazy__ = (t) => ({v: undefined, t, c: false});
const __lazyDone__ = (v) => ({v, t: null, c: true});
const __force__ = (z) => {
  if (!z.c) { z.v = z.t(); z.t = null; z.c = true; }
  return z.v;
};
```

Key pieces of `Codegen.res`:

- **Pure placement (let-floating).** `compileValue(state, context, valueRef)` returns the statements it wants emitted, each tagged with the context it must live in. Owners claim what is addressed to them — a collect emitter buckets statements into its loop bodies and floats the rest upward; the top level (empty context) keeps everything that reaches it. Loop-invariant hoisting is what floating does by default, not an analysis.
- **Context** is the ordered stack of flows open on the consumer chain, each segment tagged with the collect whose emitted thunk owns that JS scope (`thunkOf`). Two sibling collects over one flow open structurally identical paths but distinct scopes; the tag is what stops a binding emitted in one thunk from being memo-reused in the other.
- **Memo** keys on `(node id, port)`; lookup reuses an entry whose context is a **prefix** of the requesting one. Lits memoise at the empty context (shared everywhere).
- **Dispatch** is by node kind. A `Collect` classifies its branches (iter / full-case / partial-case) and emits one self-contained thunk holding the entire iteration logic (for-of / if-chain / nested combinations); an opener's element / alt-payload value ports exist only inside a consuming collect's thunk, where the collect pre-memoises them. Multi-collect on one opener = one thunk per collect, each iterating independently.

`Pipeline.compile(p)` returns witnesses as data, or per-output compiled IIFEs; a not-yet-written emitter raises `Codegen.Todo` (a compiler gap, surfaced to the caller).

## Conventions

- **Sharing is opt-in via ReScript-level binding.** Two calls to `Build.lit(b, int_(5))` produce two distinct nodes (different ids, no sharing). To share, bind the handle once and reuse its ref: `let x = Build.lit(b, int_(5)); Build.app(b, f, [x.value, x.value])`.
- **One node = one binding per accessible scope**, including `Lit`s. A shared `Lit` whose payload is non-trivial (e.g. `Math.PI`) evaluates exactly once (Lits are memoised at the empty context). Trivial literals like `5` also get bound — this is uniform and worth the noise. The caveat: a node that depends on a per-iteration value re-emits inside each consuming collect's thunk, so sharing across sibling collects' loops is not preserved (see `plans/lazy-compile-design.md`).
- **Value port vs flow port** is a first-class distinction: value refs are `ValuePort(node, port)`, flow refs `FlowPort(node, port)`. A Case uncollect exposes one `<alt>` value port and one `<alt>` flow port per alt (per-alt ports — no Branch node); a `List`/`Option` uncollect exposes `element` and `flow`. An opener's element / alt-payload value port only exists inside a consuming collect's thunk, so reaching it as a value outside one is an ill-formed reference that `Check`'s flow-borne rule witnesses (see `plans/first-class-ports-design.md`).
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

Tests are inline in `Main.res`, built via text (`TextResolve.parseProgram`) or handles (`Build`). `expectOutput(program, name, expected)` compiles via `Pipeline.compile`, evals the named output's generated JS, and compares against an author-written `JsAst.expr`; `expectRoundTrip` checks `parse(print(p))` has identical wiring and that the print is stable. Each test prints the textual form and the generated JS so the pieces can be *seen* working.

## Language design philosophy

Seven principles run through the language design; the full statements,
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
- **Building blocks must build (graceful expansion).** The complex
  case must be reachable from the simple case by adding structure,
  never by rewriting into a different construct — `.map()`/`.filter()`
  being unbuildable-upon, and fold's tuple bottleneck, are the
  counterexamples. Check every proposal's "+1 steps."

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
separate from decision. One interpretation rule binds all readings:
frequency is not importance (the 80/20 counterweight) — high
frequency ranks what must be effortless, while a rare painful shape
is a breadth obligation, never a deprioritization candidate; the
most annoying loop to write can break the language even when the
common cases are trivial. Use the method frequently — reach for it
proactively when design discussion is running ahead of evidence.

A companion lens sits beside it — **what does it mean?** (ontology).
Where sampling keeps the design in contact with real code, this keeps
it in contact with *meaning*: two constructs can compute identically
and still differ in what they *are*, and the ontological choice can
select the behaviour where the results did not force it. Reach for it
when a construct is fully pinned at the level of results but you still
cannot say in one sentence what it is (worked instance: what a Delay
is, and which flow its "next iteration" binds to — the collect that
binds it or the uncollect its value descends from — an open problem in
`plans/iteration-with-state-design.md`, where the choice changes
behaviour under a commute or a product).

## Working with the user

The user designs incrementally and likes to think out loud about a step before any code is written. Rough pattern from past sessions:

- They share an intuition or partial design and invite engagement, *not* immediate implementation. ("It seems X. Does that work?" usually means "talk it through first.")
- They prefer "baby steps" — one small, well-understood addition at a time. Don't bring in extra design dimensions ("multi-close at the same time as nested at the same time as join") in one round.
- They have strong design taste — when they say something like "we don't need to walk the stack" or "join is a pure flow operation," it's worth taking literally and working out the implications, not paraphrasing or smoothing over.
- When you see a non-obvious design tradeoff, surface it and let them choose. Multiple options laid out concretely > one chosen for them.
- Before declaring something done, run the test suite (`npm start`). It currently passes 333 checks; if a change drops that count, something regressed.

## Honoured semantic limitations

Two properties that used to be assumed-but-unchecked are now enforced by `Check` (witnesses returned as data, not crashes):

- **No time travel.** Combining values from incomparable flows (siblings not on the same nesting chain) is ill-formed. `Check`'s alignment rule witnesses it (classifying bundle-mixing vs a completable time-travel gap that `Complete` fills with a Cross); the poset round is extending the context model that backs it.
- **Closed-scope leakage** used to be on this list (referencing a binding emitted inside an already-built thunk from outside it, producing JS with an out-of-scope variable). It's now structurally guarded: the memo only reuses a binding whose context is a prefix of the requesting one, and an opener value port (element / alt payload) reached outside its consuming collect's thunk is witnessed by `Check`'s flow-borne rule. Kept as a note in case a future change bypasses the memo.

## Notes

- `rescript.json` controls the compiler: ESM output, emits under `lib/es6/` (`in-source: false`), `.res.mjs` suffix.
- `package.json` has `"type": "module"` — Node treats the emitted files as ESM.
- `lib/` is gitignored; only `.res` sources are tracked.
