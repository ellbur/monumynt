# Compile-Time Placement: Preserved Design Notes

## Status

**Not currently in use.** This document captures the compile-time
placement algorithm that lived in `src/Compile.res` through commit
`750b14c` (2026-05-16). We removed it in favour of a simpler runtime-
lazy compile so the language design could move forward without
optimisation logic in the compiler.

This algorithm is worth keeping a memory of for two reasons:

1. It's a clean, principled compile-time form of laziness for a pure
   dataflow language, and may be the right approach again if we ever
   want to make the generated JS tight (no thunks, no force overhead).
2. The bookkeeping it discovered — loopDepth, sink-then-move,
   placeholder-move-on-first-consume — is non-obvious. The notes
   below are the only place it's written down.

The full implementation is at commit `750b14c`, file
`src/Compile.res`. What follows is a guide to what was there and why.

## What it did

For a pure dataflow language, the compile chose where each App
binding goes such that:

- The binding's scope is at or deeper than each of its inputs'
  scopes (visibility from inputs).
- The binding's scope is at or shallower than the shallowest common
  ancestor of its consumers' scopes (visibility from consumers).
- The binding's scope has the same loop-iteration-frequency as its
  inputs (sinking past a list-iter would multiply the cost of the
  binding by the loop's length).

Picking the deepest scope satisfying all three is consumer-driven
placement, equivalent in semantics to runtime laziness for pure
code. The win: an App whose only consumer is inside an option's
some-body or a case-split alt automatically lands in that body and
runs only on iterations where the body fires, without any runtime
overhead. Generated JS reads like hand-written tight loops.

## The three pieces of machinery

### 1. `loopDepth` on `scopeRef`

Each scope tracked how many ListLoop bodies wrapped it (option
bodies and case-split alt bodies don't count — they're conditional,
not iterative). The sink target had to have the same `loopDepth` as
the App's eager scope; otherwise sinking into a deeper loop would
turn one computation into N computations.

The flip-side guarantee: an App whose only consumer is inside a
loop body but whose own inputs are all outer stays outside the loop
(computed once total). The loopDepth cap is what enforces this.

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

Apps emitted eagerly at `deeper(args' scopes)` during DFS — same as
the original eager compile. Consumer info was collected as a side
effect:

- `go(App)` recorded the App as an `AppCons` consumer of each arg.
- `flowFor(NodeFlow(Open _))` recorded the Open as a `StructCons`
  consumer of its input at `parentScope` (the input is pinned: the
  for-of header / discriminator call / if-test reads it there).
- Each `consumeXxxClose` recorded the close as a `StructCons`
  consumer of `branch.value` at the push/assign scope (alt scope
  for case/filter; innermost iter scope for list/option). This was
  the move that let alt-only computations sink into their alt body
  — without it, no recorded consumer would point into the alt body
  at all, since "Close-as-consumer" via the alt's interior is what
  the runtime actually sees.

After DFS, the sink pass walked pendingApps in reverse-topo order
and computed each App's target:

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

The move pass then spliced any App whose target differed from its
eager scope out of the eager buffer and appended to the target
scope's appBuf. Apps that didn't sink were untouched (preserving
DFS-order topological correctness). Walked in forward DFS order so
each target's appBuf accumulated in topological order itself.

### 3. Placeholder-move-on-first-consume

The trickiest piece. Each loop / dispatch pushed a placeholder stmt
into its parent buffer at flowFor time, to be replaced at finalisation
by `[…preLoopBuf, for-of]` (or the dispatch analog). But bindings the
consume's value-subtree emitted into the same parent buffer would
land *after* the placeholder, and after finalize would end up after
the for-of — TDZ when the for-of body referenced them.

The fix was to splice the placeholder past those bindings at the end
of each consume, so the wrapper ended up after its inputs:

```rescript
let moveToEnd = (buf, stmt) =>
  switch buf->Array.indexOfOpt(stmt) {
  | Some(i) =>
    buf->Array.splice(~start=i, ~remove=1, ~insert=[])
    buf->Array.push(stmt)
  | None => ()
  }
```

But on **shared** placeholders (multi-close on one opener), the
second consume's move would skip past stmts a sibling consume's
parent had emitted between consumes. Fix: per-flow `mutable
placeholderMoved: bool`, set on the first move; subsequent consumes
left the placeholder alone.

Of the three pieces, this one accreted as a series of fixes for
specific test failures rather than falling out of the design — a
fragile-feeling sign that the lazy-flow-construction model's "push
placeholder early, splice late" interacts unhappily with consumer-
side eager emission.

## What working examples look like

For pure code, sinking produced JS that read like a hand-optimised
loop. Two examples from the test suite at the time:

**Per-iter computation only used in option-some-body** sinks into
the if:

```js
for (const v1 of v0) {
  const v3 = (x => x % 2 === 0 ? x : undefined)(v1);
  let v4;
  if (v3 !== undefined) {
    const v5 = (x => x * 10)(v1);   // sunk here
    v4 = v5;
  }
  v2.push(v4);
}
```

**Outer-only computation used inside a loop** stays outside (the
loopDepth cap):

```js
const v3 = 100;
const v4 = 50;
const v5 = ((a, b) => a + b)(v3, v4);   // outside, once
const v2 = [];
for (const v1 of v0) {
  const v6 = ((a, b) => a + b)(v5, v1);
  v2.push(v6);
}
```

## Why we stepped back

Three reasons:

1. **Semantics first.** Most of the language design is still
   open — flow kinds, structured values, iteration rails, sum-of-
   product types. Compile-time optimisation was paying down
   debt the language hadn't accumulated yet.
2. **Coverage gaps.** The compile-time approach can't help when
   placement depends on runtime values — a loop that turns out to
   be empty, an option that turns out to be None. Runtime laziness
   handles both for free.
3. **Increasing fragility.** The placeholder-move-on-first-consume
   patch was added in response to a test failure that exposed an
   architectural mismatch (early placeholder push vs late binding
   emission). The patch worked but didn't feel like a clean
   resolution of the underlying tension.

## When it might come back

If runtime laziness becomes a bottleneck — i.e. the per-binding
object allocation and per-access dispatch through `force(…)` show up
in profiles for some real workload — this algorithm is one principled
way to recover tight-loop JS for the subset of programs where
placement *can* be decided at compile time.

*Update (2026-07-06):* profiles are the weaker of the two reasons
this comes back. The stronger one — sufficient on its own — is that
the generated JS is read: a reader who sees one conceptual loop
compiled into five thunked loops doesn't wait for benchmarks, they
ask "how can this possibly scale?" and conclude the model is naive.
So the hybrid below should be built once the semantics settle,
whether or not laziness ever shows up in a profile — what "when it
might come back" gates is the sequencing, not the decision. The
full argument is under "Deferred, not conditional" in
`lazy-stream-placement-design.md`.

The plausible roadmap:

1. Keep runtime laziness as the default (correct in all cases).
2. Add a strictness analysis: each binding tagged "always demanded"
   (consumer set is unconditional from its scope downward) or
   "conditionally demanded."
3. For "always demanded" bindings, do compile-time placement (this
   algorithm). Emit strict `const v = …` instead of `lazy(…)` /
   `force(…)`.
4. Keep lazy thunks for "conditionally demanded."

The hybrid would give tight loops for the unconditional fragment
(most of typical code) without giving up the coverage of laziness
for the conditional fragment.

## Concrete pointers

The full implementation lives at commit `750b14c`,
`src/Compile.res`. Key landmarks in that file:

- Type defs: `scopeRef` (with `loopDepth` and `appBuf`),
  `consumerInfo`, `pendingApp`, `compileCtx`.
- Helpers: `mkScope` / `loopDepthOf` / `scaScopes` / `scaAll` /
  `descendToEagerLoopDepth` / `recordConsumer` / `moveToEnd`.
- DFS-side: consumer recording in `go(App)`, `flowFor(NodeFlow(Open _))`,
  and each `consumeXxxClose`.
- Post-DFS: `sinkApps`, `moveSunkApps`, the appBuf-prepending loop in
  `compileToBody`.
- Placeholder bookkeeping: `placeholderMoved` / `dispPlaceholderMoved`
  fields on iter/dispatch data, the move-only-first-consume calls at
  the end of each consume.

If reviving, start by re-reading commit `750b14c` end-to-end before
touching anything; the pieces only make sense together.
