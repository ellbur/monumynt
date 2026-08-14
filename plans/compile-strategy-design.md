# Compile Strategy: The Functional Rebuild

Status: planned — a strategy document. Nothing here is implemented. It
lays out the compiler that will replace the current `src/Compile.res`,
whose *semantics* it keeps but whose *architecture* it discards. The
current implementation is described in `lazy-compile-design.md`; this
document is the planned successor, contrasted with it throughout.

The plan in one line: stop extending a single mutating depth-first walk,
and rebuild the compiler as a **pipeline of pure passes** — a recursive,
non-mutating function that compiles a node by first compiling its
dependencies.

Companion documents:

- `lazy-compile-design.md` — the current implementation's semantics, which
  largely survive.
- `placement-algorithm-notes.md` — the retired mutating placement pass,
  whose failure mode is this document's cautionary tale.
- `time-travel-programs-design.md` — the completion pass this pipeline
  hosts (see "A node reached in two contexts").
- `transformation-levels-design.md` — what the front half of this pipeline
  is.
- `core-model.md` — the representation this compiler consumes (ports-
  first; see `src/ARCHITECTURE.md` for the decision record of the now-
  retired first-class-ports round).

Terminology: **uncollect/collect** in the design vocabulary; the code
still says Open/Close.

## Why a rebuild, not a tweak

`src/Compile.res` is already the second architecture in this repo (eager
placement through `750b14c`, runtime-lazy since), and both were built the
same way: one depth-first walk over the Expr, a `compileCtx` full of
mutable state (`memo: Map`, `outerStmts`, per-thunk `bodyRef` buffers
pushed to in place), analysis and emission interleaved in that single
walk.

That shape has failed once already, instructively. The retired placement
algorithm's worst piece — placeholder-move-on-first-consume, flagged in
`placement-algorithm-notes.md` as "a series of fixes for specific test
failures rather than falling out of the design" — was the direct cost of
computing a *downstream-dependent* fact (where consumers place a binding)
inside the same mutating pass that was already emitting code. Early
placeholder push, late binding emission, splice to reconcile: the mutation
order became load-bearing, and every fix made it more so.

The load that is coming is dominated by exactly that kind of fact —
something the compiler learns from *downstream* nodes:

- **Completion** (`time-travel-programs-design.md`) derives flow nesting
  from *terminations* — the most downstream nodes there are.
- **Consumer-set placement** (`lazy-stream-placement-design.md`, a
  deferred but committed optimisation) partitions per-element work by which
  outputs read it.
- **Registers** (`iteration-with-state-design.md`, "The Delay
  back-edge: the write half is a node") need a write index a root-first walk cannot even build, because a
  write half can be root-unreachable.
- **Multi-level programs** (`transformation-levels-design.md`) put whole
  derived programs between the program of record and the code generator.

One more mutating walk with more fields on `compileCtx` is the wrong
instrument. The rebuild is a pipeline of pure functions.

### What survives

The rethink is architectural, not semantic. These commitments are kept,
and the rebuild must reproduce them:

- **The runtime-lazy baseline.** Every node a memoised binding, every
  reference a force; correctness never depends on an analysis
  (`lazy-compile-design.md`). For stream flows, the same stance
  transposed: one memoised cell per node (`lazy-stream-placement-design.md`,
  "The baseline, revisited").
- **Multi-close independence.** Each collect is a self-contained consumer;
  sibling collects on one flow compile to independent iterations — though
  what they iterate over may now be a shared point-indexed structure (see
  "A node reached in two contexts").
- **The join law and the any-list rule**, read off Join operands
  (`lazy-stream-join-design.md`).
- **Completion is translation only.** Zero runtime representation of
  unresolved nesting; the compiler consumes completed programs
  (`time-travel-programs-design.md`, commitment 1).
- **The compiler is just another consumer of the derived view.** It sees
  the fully-lowered level-0 denotation, same as the IDE
  (`transformation-levels-design.md`).
- **Placement optimisation is deferred, not conditional.** The pipeline
  reserves the slot; it does not fill it now.

## The functional discipline

The core is one shape:

```
compile : (state, context, ref) -> (state, result)
```

A node is compiled by recursively compiling its inputs, then itself. No
emission into shared mutable buffers; no analysis by side effect. Three
techniques make everything that *looked* like it required mutation
expressible in this shape.

**1. A compile result is a record, not just code.** The result of
compiling a node carries whatever later steps need: the name or expression
to reference it by, the statements it wants emitted, *where* those
statements must live (its required context — see below), what flow
variables it ranges over, what kind of thing it is (value cell, stream
cell, register read). The retired algorithm smuggled this information
through side tables (`consumers`, `pendingApps`, `appTarget`); here it
rides the return value.

**2. Downstream dependence becomes an earlier pass.** A recursive top-down
function cannot know about consumers — unless something already walked the
consumers and handed the answer down as context. That is the general law
of this design: **every "the compiler needs to know something about
downstream" problem is solved by a preceding pass whose output is passed
down as context to the next pass.** Completion ordering, consumer sets, the
write index: each is a pass over the whole program that runs *before* the
pass that needs it. Passes convert downstream dependence into upstream
context. Each pass emits its own intermediate form, and each form is
printable and testable on its own.

**3. The memo threads through.** The program is a DAG (with
identity-carrying nodes), not a tree, so the compile must detect
already-visited nodes. The memo — a map from node id (plus context; see
below) to compile result — is part of `state`, passed down into recursive
calls and returned up. Whether `state` is a persistent map threaded
through returns or a mutable map whose scope is confined to one pass
invocation is an implementation choice; the property that matters is that
each pass is a *function of its inputs* — same program in, same output out,
no dependence on traversal order. (ReScript note: `Belt.Map` is
persistent; the stdlib `Map` is a JS Map. The pure-threading spelling is
the default; a locally-scoped mutable map behind a pure interface is an
acceptable optimisation, never an architecture.)

### Statement placement without buffers

The one place the current compiler's mutation looks essential is statement
emission: bindings are pushed into whichever `bodyRef` buffer is under
construction. Functionally this is let-floating. `compile` returns its
statements tagged with the context each must live in, and the *owner* of
each context — the collect thunk being assembled, or the top level — keeps
the statements addressed to it and floats the rest upward in its own return
value. `deeper(args' bodies)` survives as a pure computation on the args'
results (each result says what context it required); the buffer push
becomes a tagged return. No shared structure is written; nesting of emitted
code follows the recursion.

## The pipeline

Five passes (stages 0–4), each a pure function, each with a printable
output; the diagram's sixth stage, print, is the existing `JsPrint`, not
a new pass.

```
program of record (node set, versions of the step-DAG)
  │  0. derive      — run level-1 structure down to level-0
  ▼
level-0 core
  │  1. check       — well-formedness, witnesses or pass
  ▼
checked core + analysis facts
  │  2. complete    — flow-structure completion (per output)
  ▼
committed core (+ insertion report, faint-renderable)
  │  3. annotate    — flow-variable sets, write index,
  │                   (later: consumer sets / strictness)
  ▼
annotated core
  │  4. codegen     — recursive, memoised, context-passing
  ▼
JsAst  →  5. print (existing JsPrint)
```

**0. derive.** Consumes the multi-level structure: every abstract node
(reduce-close, and each future catalog species) is replaced by its lens
expansion; `DerivedPort` references resolve against expansion shapes.
Detailed under "Multi-level programs" below. Level-0 nodes pass through
untouched, so a program that is already level-0 is its own derivation
(conservativity, same as completion's).

**1. check.** The whole-diagram quotient checks, with witnesses:
port-inventory validity, join operand adjacency, productivity (needs the
read/write pairing), flow-context alignment and bundle provenance
(`types-design.md`, `bundle-provenance-design.md`). Output is either a
witness list (stop) or the input annotated with the facts the checks
computed anyway — context paths especially, which pass 2 wants (detection
is the front half of completion).

**2. complete.** The elaborator of `time-travel-programs-design.md`:
harvest directed constraints from terminations and authored flow
operations, extend the partial order (canonical table, then heuristic
order, per that document), realise the assignments as inserted operators —
Cross for flow–flow nesting, commute chains for lifts
(`product-flows-design.md`; Cross replaces Incorporate for the
sibling-opens case). Output: a completed core plus the insertion report
addressed to authored node ids (the lens an editor renders faint, and a
test runner prints).

**3. annotate.** Cheap derived facts codegen wants handed to it rather than
discovered mid-walk: for each node, the set of flows its value varies with
(the generalisation of `deeper`; also the guard for "per-iteration value
referenced outside its flow"); the write index (register read id → write
node — buildable here because the entry point is a node set, not a root);
node kinds' runtime species (lazy cell / stream cell / async cell /
incremental cell / register). This is also where the deferred placement
analyses slot when they come back: strictness tagging and the consumer-set
lattice are more annotations, consumed by codegen, changing which shape it
emits — the pipeline position is reserved now so reviving them is additive.

**4. codegen.** The recursive compile proper, described next. Emits JsAst;
the thunk shapes and emitted JS of the current compiler are the starting
spec (all 80 tests should pass with output changes reviewable as
golden-file diffs, not semantics changes).

The boundary between passes 1–3 is pragmatic — they are all cheap graph
walks and may share traversals in code — but their *outputs* stay distinct:
a witness list, a completed program, an annotation table. What matters is
that no pass both discovers a fact and consumes it through mutation.

One obligation runs through all passes: **anything a pass manufactures must
remain addressable back to the program of record.** Derive returns,
alongside the core, the map from manufactured nodes to `(authored node,
internal name)`; complete returns insertions addressed to authored anchors.
A witness found by pass 1 in derived structure must be reportable against
the authored program (through the lens), or it is not a witness the user
can walk. This is technique 1 again — results carry more than code —
applied to diagnostics.

## Context, precisely

The `context` passed down in codegen is the ordered stack of flows
currently open on the consumer chain being compiled — a context path in
exactly `bundle-provenance-design.md`'s sense (root, then one segment per
uncollect / bundle cell). Compiling a collect pushes the flow(s) it closes;
compiling an alt body pushes the cell; the value subtree of a collect is
compiled under the pushed context.

Two ingredients meet in it, from opposite directions:

- **Upstream decides the set.** Which flows a node's value varies with is a
  fact about its inputs — computed bottom-up by annotate (today's
  `deeper`, made explicit).
- **Downstream decides the order.** Which of two unrelated flows is outer
  is a fact about terminations — computed by complete and carried in the
  context that codegen passes down.

This is the answer to the time-travel wrinkle. Converting a time-travel
program to a no-time-travel program depends on downstream nodes, so the
conversion runs as its own pass (complete), and its verdict — the order in
which flows are collected — arrives at codegen *as the context*, already
settled. The recursive function never looks downstream; it is handed what
downstream determined.

Codegen's placement rule is then a pure check-and-tag: a node's required
context is the deepest prefix of the current context that covers its
flow-variable set. If the current context doesn't contain some flow the
node varies with, that is the ill-formed reference pass 1 should have
caught — an assertion here, per the honoured-limitations discipline (the
current `deeper`-trusts-input behaviour becomes "assert the input is
complete," exactly as the time-travel document commits).

## Memoisation

The memo maps **(node id, context)** to a compile result, and it threads
down and up the call stack with the rest of the state. Lookup generalises
today's `lookupMemo` rule verbatim: a stored entry is reusable when its
context is a **prefix** (ancestor) of the requesting context — a binding
emitted at the root is visible in every loop body; a binding emitted in a
loop body is not visible outside it, nor in a sibling body. Today's
`Map<int, array<(option<bodyRef>, string)>>` with its `isAncestor` scan
*is* this table in mutable form; the rebuild keeps its logic and changes
its plumbing.

Lits memoise at the empty context (shared everywhere); a node memoises at
its required context (the deepest prefix covering its flow set), so
loop-invariant work naturally lands outside loops, exactly as now.

## A node reached in two contexts

The question the memo design has to answer: what happens when the same node
is demanded from two contexts, neither of which is a prefix of the other?
Two candidate policies:

1. **One conjoined context.** The node has a single consistent context
   formed by conjoining every path that reaches it; incomparable
   requirements are an error.
2. **Compile per context.** Incomparable contexts are allowed and the node
   compiles once in each.

The two-lists program decides it. Uncollect `listX` and `listY` as
siblings (neither derived from the other), add their elements, and
terminate twice: `out1` collects `~x` then `~y`; `out2` collects `~y` then
`~x`.

```
listX -> open list => x, ~x
listY -> open list => y, ~y
x, y -> add => s
s -~> collect ~x -~> collect ~y => out1     -- ~x inner, ~y outer
s -~> collect ~y -~> collect ~x => out2     -- ~y inner, ~x outer
```

What this should *mean* is not in doubt: `out1` is, per y, the list of x+y
over all x; `out2` is the transpose. Each output's own termination chain
fully directs a nesting — for that output. The two directions are simply
different. And what the meaning wants at runtime is two *traversal orders*
of **one table of values**: the add varies with `~x` and `~y`, its values
form an n×m table indexed by iteration points, and points are order-free —
order belongs to the traversals, and the traversals belong to the
collects. (What it must **not** compile to is any single joint iteration —
an outer-product sequencing in the list monad picking one global order. The
user drew two readings; a Cartesian product in some canonical order is a
third program nobody drew.)

Neither policy as stated survives this program. Policy 1 refuses a program
with a perfectly clear meaning. Policy 2 — realised as per-chain completion
with duplicated opens — compiles the user's add once per context, and
duplicated user computation is the wrong default: sharing is opt-in via
binding, and the author bound one node expecting one computation.

The resolution has a language half and a compile half, worked out in
`product-flows-design.md`:

- **Language half.** Sibling opens are mutually invariant by construction,
  so the flows form a *product*; completion inserts one **Cross** node
  (plus a lawful Commute for the chain reading the other orientation)
  instead of per-chain incorporates. No opens are duplicated in the
  completed program.
- **Compile half.** A node whose flow-variable set spans a product's axes
  memoises **at the product context** as a point-indexed structure. For the
  eager fragment, one lazy whose thunk builds the whole table in the stored
  orientation, the other consumer indexing it transposed:

```js
const s_tab = __lazy__(() => {
  const t = [];
  for (const y of listY) {
    const row = [];
    for (const x of listX) row.push(add(x, y));
    t.push(row);
  }
  return t;
});
const out1 = __lazy__(() => /* traverse __force__(s_tab) y-outer */);
const out2 = __lazy__(() => /* traverse __force__(s_tab) transposed */);
```

The add runs once per point, whichever consumer forces first. (Whole-table
is adequate for the eager fragment because eager collects always consume
fully; under stream kinds the table refines to per-cell `Delayed` cells —
one cell per node, over a product.)

The memo rule survives verbatim; only the order it runs over grows. Product
contexts make the context order a poset rather than a tree (each axis ≤ the
product; the axes stay incomparable to each other — `product-flows-design.md`,
"The context model"), and the product context is ≤ both orientations' loop
bodies, so the table binding is reused by both consumers under the ordinary
stored-≤-requesting rule. Policy 1's conjunction is what the completion
solver does within a chain; policy 2's per-context entries remain for
placement of genuinely unrelated bindings; and the shared-value case that
motivated the question lands on neither — it lifts to the product. Genuine
incomparability on a value codegen must place never reaches codegen: where
no product exists (a dependent nesting read backwards, a within-chain
cycle), the checker clashed earlier, and codegen asserts.

### The honest costs

- **Retention, not duplication.** Two traversal orders of a product cannot
  both stream ephemeral values off one computation; whatever the slower
  consumer hasn't reached stays live — in the worst case the whole table.
  Bounded for the eager fragment (the table dies with the last consuming
  thunk); a genuinely new axis for streams (grid cells lack chain cells'
  free cursor-GC). Recompute-per-consumer is demoted to a possible future
  *opt-in* cost policy, never the default.
- **Same-order multi-close duplication is unchanged — for now.** Sibling
  collects in one order still iterate independently and re-emit
  per-iteration work (the documented cost of the simple eager model,
  `lazy-compile-design.md`); the stream baseline restores that sharing, as
  already recorded. The product mechanism fixes the *divergent-order* case,
  which per-context recompilation would otherwise have made worse rather
  than better.
- **Effects will eventually notice point order.** Once-per-point is the
  right effect semantics (each effect happens once), but *which consumer
  forces first* sets the inter-point order. The line to hold: a node on an
  effect flow has its ordering directed by that flow's structure, so
  divergent-order demands on it should be unreachable; if a program
  achieves one anyway, that is a clash, not a scheduling choice. Worked out
  for real in the async/effect rounds — flagged here so the memo design
  doesn't silently decide it.
- **Streams change the sharing story again.** Under the per-node-cell
  baseline, cells restore cross-consumer sharing *within* a context; the
  consumer-set lattice, when it comes back, partitions within a context —
  context first, lattice second. (The lattice axes are a context's own
  outputs; nothing in `lazy-stream-placement-design.md` crosses contexts.)

### Why the earlier per-chain answer was dropped

An earlier resolution of the two-context question made completion solve per
termination chain — performing a duplicating rescue, faintly. The product
resolution supersedes it on every axis it paid on: one faint Cross instead
of per-chain insertion sets, no duplicated opens, no duplicated work. The
surviving shape recorded in `time-travel-programs-design.md` (insertion
inventory, worked examples 1 and 4, disposition 4, open question 4): Cross
replaces Incorporate for flow–flow nesting, and contradiction narrows to
within-chain cycles, reversed dependent nestings, and bundle mixing.

## Multi-level programs

How compilation fits `transformation-levels-design.md`: the compiler never
sees a level-1 step. It sees the level-0 denotation, which pass 0 computes.
Concretely:

- **derive is the language's level-1 evaluator, run to fixpoint downward.**
  Each abstract node's catalog entry supplies pattern → expansion → port
  correspondence; derive replaces the node with its expansion and rewires
  consumers through the correspondence. Expansions may contain abstract
  nodes; derive recurses. "Run" lowers by exactly one level, and derive
  runs until level 0. The pipeline's front half is thus the meta-level
  evaluator and its back half a level-0 translator — one compiler, two
  halves, meeting at the level-0 core.
- **Completion is itself a catalog entry** (the time-travel document places
  it there), so pass 2 is, structurally, one more level-1 computation the
  compiler runs. The pipeline order — derive, then complete — reflects that
  completion's constraint harvest must see the level-0 flow structure that
  expansions introduce.
- **Internal ids must be deterministic.** Lens-internal nodes carry no
  durable minted ids (the record is explicit about this); the compiler
  still needs ids for its memo. They are minted as composites — `(host node
  id, expansion-internal name)` — never from a counter, so the same program
  derives to the identical core every time. Same program, same compilation:
  the determinism obligation completion already carries, extended to
  derive. These composite ids are compile-internal and never stored;
  nothing leaks into the program of record.
- **`DerivedPort(nodeId, portName)` resolves in derive**, against the
  expansion's shape — structural, per the representation section of the
  transformation-levels document. After pass 0 no cross-level references
  remain.
- **The history never enters the compiler.** Compilation is a function of a
  *version* (the level-0 fold of a head), not of the step-DAG. Undo,
  cherry-pick, materialize are invisible here: a materialized expansion
  arrives as ordinary level-0 nodes with durable ids, and derive passes
  them through.
- **The entry point is a node set with distinguished outputs**, not a root
  expression — forced by register write halves being root-unreachable and
  wanted anyway for multi-output diagrams (`core-model.md`;
  `src/ARCHITECTURE.md`, "Node set from day one"). The interim spelling
  `compileToBody(root, ~writes)` is acceptable scaffolding; the rebuild
  should take the honest signature — outputs plus node set — from the
  start, since the pipeline's passes (write index, per-chain completion)
  are stated over it.

## Codegen, per construct

The emitted shapes are specified in the per-construct documents; codegen's
job is dispatch. The inventory, with the compile species annotate assigns:

- **Lit / App** — memoised lazy binding at the required context; unchanged
  from today.
- **Eager collect (list / option / case / filter chains)** — one
  self-contained thunk per collect: nested for-of / if / dispatch, per
  `lazy-compile-design.md`. This is the one non-compositional spot in
  codegen: the collect compiles its value subtree *under its pushed
  context*, and the (id, context) memo is what makes the re-entry
  principled — per-element bindings memoise at the loop-body context; outer
  work memoises at its prefix and is reused, not re-emitted. What today is
  "re-emission inside each consuming close's thunk" becomes an ordinary
  incomparable-context miss.
- **Join / Commute nodes** — no runtime residue of their own; they steer
  the collect's chain walk and output construction (operand walk per
  `src/Program.res`'s Join node — the retired first-class-ports round,
  decision record in `src/ARCHITECTURE.md`; any-list rule per the join
  law; commuted output construction per `lazy-stream-commute-design.md`).
- **Stream-kind flows** — fully compositional: every node one memoised
  `Delayed` cell built from its inputs' cells; collects/joins/commutes are
  output construction over the pull interface (`zipStream` folds,
  become-the-rest, abandon-the-rest). The functional compile and the stream
  baseline are the same shape — compile-a-node-from-its-inputs *is*
  build-a-cell-from-its-input-cells — which is a quiet argument that the
  architecture is right.
- **Registers (DelayRead / DelayWrite)** — the read compiles to a `let`
  register init-before / read-at-top; the write to the assign-at-bottom
  inside the driving flow's loop skeleton, with `final` readable after;
  write index from annotate; productivity already checked in pass 1.
- **Async / incremental cells** — per their documents' runtime shapes
  (`__asyncCell__`, generation-versioned cells); both are more per-node cell
  species, so they inherit the compositional path. (JsAst already carries
  `isAsync` on arrows/functions and `EAwait`, so no AST work blocks async.)
- **Partial collect** — the three arm shapes of `partial-collect-design.md`,
  dispatched by coverage; no new machinery class.

The runtime helpers stop being three inlined lines once streams land —
`Delayed` with iterative force and path compression, `zipStream`, cell
constructors are a real (small) runtime. Whether it stays an emitted
prelude or becomes an imported module is an open packaging question below.

## What this deliberately defers

- **The placement/strictness optimisation passes.** Committed, not started
  (`placement-algorithm-notes.md` roadmap; `lazy-stream-placement-design.md`
  lattice). The pipeline reserves their slot in annotate; nothing in
  codegen may assume they don't exist (codegen dispatches on annotations,
  so a richer annotate changes output without restructuring).
- **Incremental recompilation.** The step-DAG makes "diff the core across
  versions" cheap and the pure passes make caching legal; none of it is
  needed while programs are test-sized. Determinism (same version, same
  output) is the property to protect so this stays available.
- **Concrete ReScript types** for pass outputs, the state record, and the
  memo representation — settled in code, against the ports representation,
  not here.

## Open questions

1. **Effects × point order.** The claim above — an effectful node's
   ordering is always fully directed by its effect flow, so divergent-order
   demands can't reach it — needs to be proven or weakened when
   async/effect flows are designed against this pipeline. The alternative
   (clash on effectful divergence) is the recorded fallback.
2. **The point-indexed structure's concrete shape.** Nested arrays in the
   stored orientation (transposed consumer indexes `t[j][i]`) vs a keyed
   map; where the crossed subgraph's *multiple* nodes share one table of
   records vs one table per node; and the threshold at which per-cell
   laziness starts paying (it doesn't, for eager collects that consume
   fully).
3. **Runtime packaging.** Inline prelude per IIFE (self-contained output,
   as today) vs an imported runtime module (once streams make the prelude
   non-trivial). Interacts with the test runner's `eval` harness.
4. **Memo/state representation.** Persistent map threaded through vs scoped
   mutable map behind a pure interface; and whether context paths intern to
   make the prefix test O(1) (today's `depth` int-compare trick, kept).
5. **Where the vocabulary rename lands.** The code says Open/Close; the
   record says uncollect/collect. The rebuild touches every line that would
   need renaming — doing the rename with it is cheap; doing it separately is
   churn. Lean: with the rebuild.
6. **Does check gate complete, or interleave?** Contradiction detection is
   completion's front half; the split above keeps them as separate passes
   for testability, but a single harvest-solve-classify walk may be the
   natural code shape. Decide in code; keep the outputs distinct either
   way.
