# Compile-Time Placement: Preserved Design Notes

Status: **not in use — deferred, not rejected.** This document
captures the compile-time placement algorithm that once lived in
`src/Compile.res`, replaced by the simpler runtime-lazy compile
(`lazy-compile-design.md`) so the language design could move forward
without optimisation logic in the compiler. The hybrid revival
sketched at the end is a committed future optimisation pass, not a
discarded idea (see "When it might come back").

One part *is* dead for good: the placeholder-move mechanism (§3). It
accreted as a series of bug fixes rather than falling out of the
design, and the planned rebuild's architecture exists specifically to
avoid its shape. The rest is worth a preserved memory, for two
reasons:

1. It is a clean, principled compile-time form of laziness for a pure
   dataflow language — plausibly the right approach again if we ever
   want the generated JS tight (no thunks, no force overhead).
2. The bookkeeping it discovered — `loopDepth`, sink-then-move,
   placeholder-move-on-first-consume — is non-obvious, and these
   notes are the only place it is written down.

The full implementation is at commit `750b14c`, `src/Compile.res`.
What follows is a guide to what was there and why.

## What it did

For a pure dataflow language, the compile chose where each App binding
goes, subject to three constraints:

- **Visible from its inputs.** The binding's scope is at or deeper
  than each input's scope.
- **Visible to its consumers.** The binding's scope is at or
  shallower than the shallowest common ancestor of its consumers'
  scopes.
- **Same loop frequency as its inputs.** The binding's scope has the
  same loop-iteration frequency as its inputs — sinking past a
  list-iter would multiply the binding's cost by the loop length.

Picking the *deepest* scope satisfying all three is consumer-driven
placement, semantically equivalent to runtime laziness for pure code.
The payoff: an App whose only consumer sits inside an option's
some-body or a case alt lands in that body automatically and runs only
on iterations where the body fires — with no runtime overhead. The
generated JS reads like a hand-written tight loop.

## The three pieces of machinery

### 1. `loopDepth` on `scopeRef`

Each scope tracked how many ListLoop bodies wrapped it. Option bodies
and case-split alt bodies do **not** count — they are conditional, not
iterative. A sink target had to have the same `loopDepth` as the App's
eager scope; otherwise sinking into a deeper loop would turn one
computation into N.

The flip side is the guarantee that pays off: an App used only inside
a loop body, but whose own inputs are all outer, stays outside the
loop and runs once total. The `loopDepth` cap is what enforces that.

```rescript
type rec scopeRef = {
  buffer: array<JsAst.stmt>,
  depth: int,
  parent: option<scopeRef>,
  loopDepth: int,        // ← the cap
  appBuf: array<JsAst.stmt>,
}

let mkScope = (ctx, parent, depth, isLoop) => {
  let s = {
    buffer: [],
    depth,
    parent,
    loopDepth:
      if isLoop { loopDepthOf(parent) + 1 } else { loopDepthOf(parent) },
    appBuf: [],
  }
  ctx.allScopes->Array.push(s)
  s
}
```

### 2. Consumer tracking + sink pass + move pass

Apps were emitted eagerly at `deeper(args' scopes)` during the DFS —
same as a plain eager compile. Consumer information was collected as a
side effect of that walk:

- `go(App)` recorded the App as an `AppCons` consumer of each argument.
- `flowFor(NodeFlow(Open _))` recorded the Open as a `StructCons`
  consumer of its input at `parentScope` — the input is pinned there,
  where the for-of header / discriminator call / if-test reads it.
- Each `consumeXxxClose` recorded the close as a `StructCons`
  consumer of `branch.value` at the push/assign scope (the alt scope
  for case/filter; the innermost iter scope for list/option). This
  recording is what let an alt-only computation sink into its alt
  body: without it, no recorded consumer would point into the alt body
  at all, since the close's interior is what actually consumes the
  value at runtime.

After the DFS, the sink pass walked pending Apps in reverse-topo order
and computed each App's target scope:

```rescript
let sinkApps = (ctx) => {
  for i in Array.length(ctx.pendingApps) - 1 downto 0 {
    let app = ctx.pendingApps->Array.getUnsafe(i)
    let consumers = ctx.consumers->Map.get(app.id)->Option.getOr([])
    let target = if Array.length(consumers) == 0 {
      app.eagerScope
    } else {
      let consumerScopes = consumers->Array.map(c =>
        switch c {
        | AppCons(consumerId) =>
          // Reverse-topo => consumer's target is already set.
          ctx.appTarget->Map.get(consumerId)->Option.getOr(app.eagerScope)
        | StructCons(scope) => scope
        }
      )
      let lca = scaAll(consumerScopes)
      descendToEagerLoopDepth(lca, loopDepthOf(app.eagerScope))
    }
    ctx.appTarget->Map.set(app.id, target)
  }
}
```

Reverse-topo order matters: a consumer's target is already fixed by
the time its producer is considered, so `AppCons` can read it. The
target is the common ancestor of the consumer scopes, then descended
back to the App's own `loopDepth` so the cap holds.

The move pass then spliced any App whose target differed from its
eager scope out of the eager buffer and appended it to the target
scope's `appBuf`. Apps that did not move were left in place,
preserving DFS-order topological correctness. The move pass walked in
forward DFS order, so each target's `appBuf` accumulated in
topological order itself.

### 3. Placeholder-move-on-first-consume (dead for good)

The trickiest piece, and the one that killed the design. Each loop or
dispatch pushed a placeholder statement into its parent buffer at
`flowFor` time, to be replaced at finalisation by `[…preLoopBuf,
for-of]` (or the dispatch analog). But bindings that the consume's
value-subtree emitted into that same parent buffer landed *after* the
placeholder — and after finalisation ended up after the for-of, giving
a TDZ error when the for-of body referenced them.

The fix spliced the placeholder past those bindings at the end of each
consume, so the wrapper ended up after its inputs:

```rescript
let moveToEnd = (buf, stmt) =>
  switch buf->Array.indexOfOpt(stmt) {
  | Some(i) =>
    buf->Array.splice(~start=i, ~remove=1, ~insert=[])
    buf->Array.push(stmt)
  | None => ()
  }
```

On **shared** placeholders (multi-close on one opener), a second
consume's move would skip past statements a sibling consume's parent
had emitted between consumes. The patch: a per-flow `mutable
placeholderMoved: bool`, set on the first move, so later consumes left
the placeholder alone.

This piece accreted as fixes for specific test failures rather than
falling out of the design — the fragile-feeling sign that the lazy-
flow-construction model's "push placeholder early, splice late"
interacts unhappily with consumer-side eager emission. It is the part
the rebuild is designed to never reproduce.

## What working output looked like

For pure code, sinking produced JS that read like a hand-optimised
loop.

Per-iter computation used only in an option-some-body sinks into the
`if`:

```js
for (const v1 of v0) {
  const v3 = (x => x % 2 === 0 ? x : undefined)(v1);
  let v4;
  if (v3 !== undefined) {
    const v5 = (x => x * 10)(v1);   // sunk here — runs only when Some
    v4 = v5;
  }
  v2.push(v4);
}
```

Outer-only computation used inside a loop stays outside it (the
`loopDepth` cap):

```js
const v3 = 100;
const v4 = 50;
const v5 = ((a, b) => a + b)(v3, v4);   // outside, computed once
const v2 = [];
for (const v1 of v0) {
  const v6 = ((a, b) => a + b)(v5, v1);
  v2.push(v6);
}
```

The runtime-lazy compile produces both behaviours too, but through
thunks that force on demand rather than through statically placed
`const`s — noisier output, no static analysis.

## Why we stepped back

- **Semantics first.** Most of the language design is still open —
  flow kinds, structured values, iteration rails, sum-of-product
  types. Compile-time optimisation was paying down debt the language
  had not yet accumulated.
- **Coverage gaps.** Compile-time placement cannot help when
  placement depends on runtime values — a loop that turns out empty,
  an option that turns out None. Runtime laziness handles both for
  free.
- **Fragility.** The placeholder-move-on-first-consume patch (§3)
  worked but exposed an architectural mismatch — early placeholder
  push versus late binding emission — that it papered over rather than
  resolved.

## When it might come back

The revival is committed; what "when" gates is the sequencing, not the
decision.

Profiles are the *weaker* reason. If runtime laziness ever shows up in
a profile for a real workload — the per-binding allocation and
per-access `force(…)` dispatch — this algorithm recovers tight-loop JS
for the subset of programs where placement can be decided statically.

The *stronger* reason, sufficient on its own, is that the generated JS
is read: a reader who sees one conceptual loop compiled into five
thunked loops does not wait for a benchmark — they ask "how can this
scale?" and conclude the model is naive. So the hybrid should be built
once the semantics settle, benchmark or no (the full argument is under
"Deferred, not conditional" in `lazy-stream-placement-design.md`).

The plausible roadmap:

1. Keep runtime laziness as the default (correct in all cases).
2. Add a strictness analysis: tag each binding "always demanded"
   (consumer set unconditional from its scope downward) or
   "conditionally demanded."
3. For always-demanded bindings, do compile-time placement (this
   algorithm). Emit strict `const v = …` instead of `__lazy__(…)` /
   `__force__(…)`.
4. Keep lazy thunks for conditionally-demanded bindings.

The hybrid gives tight loops for the unconditional fragment (most of
typical code) without giving up laziness's coverage of the conditional
fragment.

## Concrete pointers

The full implementation is at commit `750b14c`, `src/Compile.res`.
Landmarks in that file:

- Type defs: `scopeRef` (with `loopDepth` and `appBuf`),
  `consumerInfo`, `pendingApp`, `compileCtx`.
- Helpers: `mkScope` / `loopDepthOf` / `scaScopes` / `scaAll` /
  `descendToEagerLoopDepth` / `recordConsumer` / `moveToEnd`.
- DFS side: consumer recording in `go(App)`,
  `flowFor(NodeFlow(Open _))`, and each `consumeXxxClose`.
- Post-DFS: `sinkApps`, `moveSunkApps`, and the `appBuf`-prepending
  loop in `compileToBody`.
- Placeholder bookkeeping: `placeholderMoved` / `dispPlaceholderMoved`
  on iter/dispatch data, and the move-only-first-consume calls at the
  end of each consume.

If reviving, re-read commit `750b14c` end to end before touching
anything; the pieces only make sense together.
