# Runtime-Lazy Compile

Status: **implemented** — this is the strategy in `src/Compile.res`
today. This document records the reasoning behind it; the mechanics
live as comments in the source. Its companion is
`placement-algorithm-notes.md`, which preserves the compile-time
placement algorithm this strategy replaced (a deferred optimisation,
not a rejected one). The planned rebuild — same semantics, a pipeline
of pure passes — is `compile-strategy-design.md`.

(The code and this document say Open/Close/close throughout, matching
`Expr.res`. At the language-design level these are *uncollect* and
*collect*; the names differ, the constructs are the same.)

## The model

Every Expr node compiles to a `lazy` JS binding; every reference to
that node forces it. The compiler decides almost nothing about
placement: each binding is emitted at `deeper(args' bodies)` — as
early as its inputs allow — and runtime laziness does the rest.
"Compute only when needed" and "compute only once" are properties of
the runtime cell, not of where the compiler put the binding.

Three runtime helpers are emitted at the top of each IIFE:

```js
const __lazy__ = (t) => ({v: undefined, t, c: false});   // unforced thunk
const __lazyDone__ = (v) => ({v, t: null, c: true});     // already-computed cell
const __force__ = (z) => {
  if (!z.c) { z.v = z.t(); z.t = null; z.c = true; }      // run once, cache
  return z.v;
};
```

A cell is `{v, t, c}`: value, thunk, computed-flag. `__force__` runs
the thunk the first time and caches; every later force returns the
cache. That single mechanism gives both demand-driven evaluation and
compute-once sharing.

Node identity drives sharing. The compiler memoises one binding per
Expr id, and reuses it when its body is an ancestor of the body now
asking (`lookupMemo`). Two references to the same node therefore force
the same cell, so a shared subtree evaluates exactly once no matter
how many consumers it has or where they sit. This is why sharing is
opt-in at the ReScript level: one bound handle reused is one node is
one cell; the same expression written twice is two nodes and two
cells.

A worked example — map a list (textual input, then the JS it compiles
to; variable numbering is illustrative):

```
double = js "x => x * 2"
[1, 2, 3] -> open list -> double -~> collect => out    -- out = [2, 4, 6]
```

```js
(() => {
  const __lazy__ = (t) => ({v: undefined, t, c: false});
  const __lazyDone__ = (v) => ({v, t: null, c: true});
  const __force__ = (z) => { if (!z.c) { z.v = z.t(); z.t = null; z.c = true; } return z.v; };

  const v0 = __lazyDone__([1, 2, 3]);        // the Lit, shared at top level
  const v1 = __lazy__(() => {                // the collect: one self-contained thunk
    const out = [];
    for (const elem of __force__(v0)) {
      const v2 = __lazyDone__(elem);         // per-element value binding
      const v3 = __lazy__(() => (x => x * 2)(__force__(v2)));   // the App
      out.push(__force__(v3));
    }
    return out;
  });
  return __force__(v1);
})();
```

The Lit is a top-level `__lazyDone__`, memoised at the outermost body,
so every consumer everywhere shares it. The App and the per-element
value live inside the collect's thunk, forced only as the loop runs.

## Closes are self-contained thunks

Each Close compiles to exactly one lazy whose thunk holds the entire
iteration logic — a for-of, an if, an if-chain, or nested
combinations of those. There is no preprocess pass, no placeholder
splicing, no finalisation step. A close is a pure consumer that
attaches to an existing flow lazily. (The replaced compile built
loop/dispatch skeletons eagerly and spliced consumers into them
afterwards; that machinery — scope buffers, a pre-loop buffer,
placeholder finalisation — is what `placement-algorithm-notes.md`
preserves.)

**Multi-close on one opener** compiles to one lazy per close, each
thunk iterating independently. The consequences:

- Sharing *within* one close, across its own iterations, is preserved
  by the per-cell memoisation.
- Sharing of inner per-iteration work *across* sibling closes' loops
  is **not** preserved — each sibling thunk re-emits and re-runs that
  work. This is the price of the simple model.

**Mixing close kinds on one case-split works.** Put both a case-close
and a filter-close on the same split: the case-close demands
exhaustiveness (its if-chain ends in `else throw`), the filter-close
pushes only in its matching alt. Each is its own thunk with its own
dispatch, so they compose without interference — at the cost of
running the discriminator once per consuming thunk rather than once
total.

## Output form for iter chains

An iter close may close a chain of ListIter and OptionIter openers,
with any number of Joineds lifting the output up the chain. One rule
sets the output form:

> **Any list in the walked-up chain ⇒ the output is a list.**

Concretely: any list level makes the output `const out = []` plus one
`out.push(…)` per chain-firing. A chain of options all the way makes
it `let out;` plus an assign, set only if every option fires. The
three mixed cases:

- `List<Option<X>>` joined → a list of just the defined values: push
  when Some, skip when None.
- `Option<Option<X>>` joined → a single value, set iff both options
  fire.
- `Option<List<X>>` joined → a list, built only when the outer option
  fires.

The implemented `Joined` wrapper is one operand short of the
language-level design, where **join is a binary flow operation** — an
outer flow and the flow immediately inside it, combined, with the
combined flow firing exactly when the inner operand fires
(`lazy-stream-join-design.md`, "Join is a binary flow operation").
Under that design the any-list rule is a theorem about the combined
flow's kind rather than a compile-time special case. Each `Joined`
reads as that adjacent-pair join with the outer operand implied —
absorbing the named flow's next enclosing level — and the compiled
behaviour above is exactly that absorb reading, unchanged.

## What laziness buys

The two placements the compile-time algorithm computed by analysis
fall out here for free:

- **Sink-into-conditional.** An App consumed only inside an option's
  some-body or a case alt is a lazy forced only when that body runs.
  No analysis needed — the thunk is simply not forced on iterations
  where the body does not fire.
- **Stay-outside-loops.** An App whose inputs are all loop-invariant
  is forced on the first iteration and cached; the work happens once,
  not once per iteration.

Laziness also covers what compile-time placement *cannot*: demand
that depends on runtime values. A loop that turns out empty, an option
that turns out None — the thunks are simply never forced. No static
placement can express "run this only if the list is non-empty."

## Costs, and the way back

The generated JS is noisy and carries runtime overhead: one object
allocation per binding, a `__force__` dispatch per reference, and
duplicated iteration for multi-close.

The noise carries a cost profiles do not measure: the output is read.
A reader who sees one conceptual loop compiled into five thunked loops
concludes the model cannot scale. So the way back is **committed, not
contingent** — deferred until the semantics settle, not until a
benchmark complains (`lazy-stream-placement-design.md`, "Deferred,
not conditional").

The way back is a hybrid: keep runtime laziness as the
correct-everywhere default, add a strictness analysis, and for the
always-demanded fragment emit strict `const` bindings placed at
compile time — recovering tight-loop JS where placement *can* be
decided statically, without giving up laziness's coverage of the
conditional fragment. The full sketch is under "When it might come
back" in `placement-algorithm-notes.md`.

The reason not to do it now: most of the language design is still
open, and optimisation logic in the compiler was paying down debt the
language had not yet accumulated. Semantics first.

## Carrying forward to streams

When stream flows arrive, the same reasoning gives the baseline
strategy: one memoised stream cell per node — the "Shape C" that
`lazy-stream-placement-design.md` first dismissed — with the
consumer-set lattice analysis held back as the optimisation to revive
later ("The baseline, revisited" in that document). One difference
works in streams' favour: the stream baseline *restores* the
cross-close sharing this compile gives up, because sibling closes pull
from the same memoised per-node cells rather than each re-running the
work.
