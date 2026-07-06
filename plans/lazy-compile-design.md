# Runtime-Lazy Compile

## Status

**Implemented** — this is the strategy in `src/Compile.res` today
(2026-07-06). This document records the design decisions behind it;
the mechanics are documented as comments in the source. Companion to
`placement-algorithm-notes.md`, which preserves the compile-time
placement algorithm this one replaced (retired at commit `750b14c`).

## The model

Every Expr node compiles to a `lazy` JS binding; every reference
forces. The compiler decides almost nothing about placement — each
binding goes at `deeper(args' bodies)` (eager), and runtime laziness
handles "compute only when needed" and "compute only once"
automatically.

Runtime helpers emitted at the top of each IIFE:

```js
const __lazy__ = (t) => ({v: undefined, t, c: false});
const __lazyDone__ = (v) => ({v, t: null, c: true});
const __force__ = (z) => {
  if (!z.c) { z.v = z.t(); z.t = null; z.c = true; }
  return z.v;
};
```

Node identity drives sharing: the compiler memoises bindings per
Expr id, reusing an existing binding when its body is an ancestor of
the requested one. Two references to the same node force the same
lazy, so a shared subtree evaluates exactly once no matter how many
consumers it has or where they sit.

## Closes are self-contained thunks

Each Close compiles to one lazy whose thunk contains the entire
iteration logic — for-of, if, if-chain, or nested combinations.
There is no preprocess pass, no placeholder splicing, no
finalisation step: closes are pure consumers that attach to existing
flows lazily. (The retired compile built loop/dispatch skeletons
eagerly and spliced consumers in afterwards; that machinery — scope
buffers, `preLoopBuf`, placeholder finalisation — is described in
`placement-algorithm-notes.md` and lives in full at commit
`750b14c`.)

Multi-close on one opener compiles to one lazy per close; each thunk
iterates independently. Sharing of inner per-iteration work across
sibling closes' loops is *not* preserved — this is the cost of the
simple model. Sharing within one close, across its own iterations,
is preserved by per-lazy memoisation.

Mixing filter-close and case-close on the same case-split works: the
case-close demands exhaustiveness (its if-chain ends in `else
throw`), the filter-close pushes only in its matching alt. Each is
its own thunk with its own dispatch.

## Output form for iter chains

An iter close may close a chain of ListIter and OptionIter openers,
with any number of Joineds lifting the output up the chain. The
output form follows one rule: **if any iter in the walked-up chain
is a list, the output is a list** (`const out = []` plus a push per
chain-firing); if the whole chain is options, the output is a single
value (`let out;` plus an assign, set iff every option fires).

Consequences worth stating:

- `List<Option<X>>` joined produces a list of just the defined
  values — push when Some, skip when None.
- `Option<Option<X>>` joined produces a single value, set iff both
  options fire.
- `Option<List<X>>` joined produces a list, built only when the
  outer option fires.

## What laziness buys

The two placement behaviours the retired algorithm computed at
compile time fall out for free:

- **Sink-into-conditional.** An App consumed only inside an option's
  some-body (or a case alt) is a lazy that's only forced when that
  body runs. No analysis needed.
- **Stay-outside-loops.** An App whose inputs are all loop-invariant
  is forced once on the first iteration and cached thereafter; the
  work happens once per loop, not per iteration.

Laziness also covers cases compile-time placement *cannot*: when
demand depends on runtime values (a loop that turns out to be empty,
an option that turns out to be None), the thunks are simply never
forced.

## Costs, and the way back

The generated JS is noisy and carries runtime overhead: one object
allocation per binding, a `__force__` dispatch per reference, and
duplicated iteration for multi-close. If that ever matters, the
plausible path (detailed under "When it might come back" in
`placement-algorithm-notes.md`) is a hybrid: keep laziness as the
correct-everywhere default, add a strictness analysis, and emit
strict `const` bindings with compile-time placement for the
always-demanded fragment.

The reason we're not doing that now: most of the language design is
still open, and optimisation logic in the compiler was paying down
debt the language hadn't accumulated yet. Semantics first.

The same reasoning carries to stream flows when they arrive: the
stream analog of this strategy is one memoised stream cell per node
(the "Shape C" that `lazy-stream-placement-design.md` originally
dismissed), with the consumer-set lattice analysis as the
optimisation to revive later — see "The baseline, revisited" in
that document. One notable difference: the stream baseline restores
the cross-close sharing this compile gives up, because sibling
closes pull the same memoised per-node cells.
