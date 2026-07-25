# src — the compiler, architecture

This file is the **architecture of the compiler, written as code**:
types, working building blocks, and the passes. Design questions stay
in `plans/`; this file records how the *code* is shaped and which
decisions it took.

It follows the sequencing of `plans/implementation-strategy.md`:
representation first (ports, node set), text surface early (test
leverage), the compiler as pure passes against that representation.

## Module map

Representation and authoring:

| module | status | what it is |
|---|---|---|
| `Program.res` | working | The program of record: ports-first nodes (`ValuePort`/`FlowPort`), uncollect/collect vocabulary, binary Join, per-alt ports (no Branch), Delay read/write pair, **Aggregate/Disaggregate** (struct construction / field projection — pure value nodes, one value port per field on the Disaggregate side), program = **node set + distinguished outputs**. Port inventories, canonical `dump`/`equal`. Coverage is read off **cell sets**, not alt ports: `branchCells` walks a branch flow to the cells of one bundle it spans (a direct alt port is the singleton `{A}`; a partial collect's merged flow is the union of its own branches', recursively), and `classifyCollect` is covering-vs-partial over those unions — so a collect's branches may be single alts, merged flows, or a mix (the design's HTTP program: two singletons and a pair). `CaseFull` is therefore "the covering configuration of the same node", not a sibling construct. The one carve-out keeping it compatible: a LONE branch on anything but a direct alt port TERMINATES its flow (an iter chain, or the option-close lift of a merged flow) rather than re-merging the same cells. |
| `Build.res` | working | Typed handles over `Program` ("strings below, typed handles above"). The builder also *collects the node set* — that is how root-unreachable write halves stay in the program. |
| `Context.res` | working (v0) | Context paths (bundle-provenance sense) computed structurally; prefix-rule merge. Shared by Check, Codegen, and TextResolve. Incomparable = raise on the linear path. **Cell-set steps landed**: a bundle step in a path is a cell SET, not a single cell — `cellSet` walks a flow to the cells it spans (a case-alt flow is the singleton `{A}`; a partial collect's merged flow is the union of its branches', computed by walking and never stored — `partial-collect-design.md`, "Expr level"), and `cellContains` / `stepAvailableAt` are the **containment theorem** as a step-availability relation: a value borne at `{A, B}` is available inside each constituent cell (`{A} ⊆ {A, B}`), by the same rule that lets a root-context value into any cell — "parent scope is subset order doing what it always did". `isPrefix` (hence `merge`), `Check`'s flow-borne containment, and `Codegen.matchChain` all match steps through it, which is what lets a computation AT the merged context compile. Strictly one-directional: it never moves a value *out* of a constituent, so an `{A}`-borne value read at `{A, B}` still witnesses, and sibling cells still clash as bundle mixing. Partial OVERLAP (`{A,B}` vs `{B,C}`, meeting at `{B}` as an inferred incorporate) and lifting the cell layer into `Poset.t` itself remain the poset round's. Also owns `throughCommutes`, the **transposing commute's whole compilation**: over a crossed pair commute is transpose, a re-reading rather than a restructuring, so a commute output port DENOTES its operand swapped and the transposed consumer becomes an ordinary product chain in its own order (the shared table already serves every k! reading). It is unconditional here and GATED by its callers — only the product matchers resolve, and they demand the resolved flows be axes of one constructed product — so the other operation the word names, the directed sequence, is untouched. **First Poset wiring landed**: `pathToPoset` / `crossProduct` / `productsIndex` lift the sibling-combine question to `Poset` — a program's Cross nodes build the product index `Poset.merge` consults. A Cross operand is lifted through `flowLayers`, which reads a **join chain as the SEQUENCE of layers it is** rather than as one opaque axis — that is what gives a FILTERED axis an identity in the poset (`join(list, alt)` is the chain `list > alt`, exactly how a value borne on it reports itself), so the product `{(list > alt) || Y}` covers the combine and the two sides agree. The same round fixed a real over-report next door: `sourceAxisFlows` of a Join used to include the axes the join itself INTRODUCES, so a collect over `join(list, case-alt)` reported the list axis as surviving it — the axis is introduced by the join and consumed by the collect, and nothing survives. (Dropping it moved one witness: an operand pair that REPEATS an axis used to be caught incidentally by that over-report, and is now named by `Annotate.crossViolation` for what it is, `Poset.res`'s repeated-flow diamond.) Also owns the **flow-variable set walks** (`introducedAxisFlows` / `sourceAxisFlows` / `axisFlows` / `valueAxisFlows`, returning flow *refs*; `Annotate` re-exports the key-set views), because the context report needs to *name* axes: `collectRemainderFlows` is the axes a collect branch's value varies over that the branch's flow neither iterates nor is determined by, and `remainderPath` reports **the surviving axes** for a collect (or a register's `final`) over one axis of a product ("a collect over a crossed axis reports `{Y}`") — at ANY width: with one surviving axis the path is exact, and with several (a rank-3 product collected over one axis leaves `{Y, Z}`) it is the *flattening* of the surviving product, in the combine's own operand order, to be read as the SET of axes that must be open. That convention is what `Codegen.matchChain` honours by matching a path's flows set-wise; the poset-VALUED report (`Poset.t` in place of the path, order-freedom in the type rather than in a convention) is still the poset round's. |
| `Poset.res` | working (algebra, unit-tested) | The **series-parallel context** — the poset generalization of the linear path (the Fork-A discussion, ARCHITECTURE poset round). Built by SERIES (nesting) and PARALLEL (Cross) composition, so every well-formed context is SP; the non-SP "N" is a repeated-flow diamond (align-vs-cross unresolved), witnessed not represented. Provides the `≤` primitive (`axes-⊆ + order-extends`) and `merge` (comparable → the deeper; siblings → the **exact-axis** constructed product, not a covering superset — `leq` is monotone `⊆` but a combine's home is `==`, since a flat cross builds no sub-products; else `Incomparable`, the completion gap — an under-determined cross is just another time-travel program). Axis keys are strings — pure, decoupled from Program. Products + nesting only; cells (⊇ polarity) arrive with partial-collect's merged context. **Wired into Context** for the alignment admit (`Context.productsIndex`); the full context-model migration (Cross output ports, poset-valued contexts everywhere) is the rest of the poset round. |

The compile pipeline (`compile-strategy-design.md`; each pass a pure
function with a printable output):

| pass | module | status |
|---|---|---|
| 0 derive | `Derive.res` | honest identity (no abstract node species exist, so every program is level-0). The catalog architecture — pattern/expansion/correspondence, composite ids, the origins map — is recorded in its header for when reduce-close arrives. |
| 1 check | `Check.res` | Implemented: port-exists, write-count, **alignment** (now with the **mixing / time-travel classification** folded in — walks the two incomparable paths to their first divergent step: sibling cells of one split ⇒ `bundle-mixing`, otherwise ⇒ a time-travel candidate that is **admitted iff a constructed Cross covers its exact axes** — `Context.productsIndex` + `Poset.merge` — else ⇒ `time-travel`; and now **full-span** — a value port's combine is re-verified with `Context.posetValueContext`, a poset-aware recomputation that merges sibling axes through the constructed products and so reaches EVERY combine, not just the first sibling pair, so an under-covered n-ary consumer like `f(x,y,z)` with only `{X,Y}` crossed is witnessed as `time-travel` at the Check level rather than admitted on its first coverable pair and left to Codegen), **join-adjacency** (an inner operand opens exactly at the outer flow's interior — computed by `Context.flowInterior`, which flattens a Join outer through its stacked layers, so a nested flatten like flatten-then-filter is not wrongly rejected against a single-layer `[outer]`; with one carve-out that is the Cross's own law — two axes of one CONSTRUCTED product are adjacent BY the product, rectangularity, so a commute over a crossed pair passes while a commute of two uncrossed siblings still witnesses. The test is `Poset.leq` CONTAINMENT — "both axes of one product" — not the exact-span discipline a combine's home gets, which is what makes a rank-3 swap of two non-neighbouring axes lawful: a product has no "between"), **invariance** (Cross operands must be mutually invariant — the Cross round's first step, consuming Annotate's flow-variable sets), **order-demand** (a Delay's flow must own a total order — `delay-ontology-design.md`'s adopted per-kind half, reading `OrderDemand.orderOf`'s kinds table the way `checkCross` reads Annotate's invariance fact; the cell it reaches today is SURPLUS, a register over a whole product, which is `product-flows-design.md`'s owed "smallest first step" 1; `Degenerate` — a bare option / case alt, ≤1 firing — passes, since inert is not ill-formed), **flow-borne** (program boundary **and** the general interior rule — a collect branch whose value is borne on a flow it does not iterate, exact for element/alt-payload **and merged-flow** interiors, its containment read as a SET so a surviving axis CROSSED with one the collect iterates is admitted — held open by the enclosing traversal, the fibered reading — while an uncrossed sibling still witnesses; step availability now runs through `Context.stepAvailableAt`, so a merged `{A,B}`-borne value is readable inside its constituent `{A}` while a cell-borne value read at the merged context witnesses — the containment theorem's one-directionality, previously a codegen `failwith`; Join/Commute/Cross interiors defer to the poset round), **unconstructed-meet** (values on overlapping cell sets combine at their meet — "overlap is incorporate, not a clash" — and `Context.merge` takes them there whenever the meet is a set the program CONSTRUCTED, a single cell always being one; a wider meet with no partial collect spanning it has no constructed home, exactly as a sibling combine with no covering product has none, and is now named as such instead of being misfiled as `time-travel` with "insert a Cross" as its remedy), **coverage** (malformedness, plus the design's **disjointness demand** read off CELL SETS — "two branches whose cell sets share a cell would both fire when B fires, and the law's 'the firing branch' would not refer" — so a merged-flow branch overlapping a singleton one witnesses, which a port-name comparison could not see, every merged flow's port being `flow`). Stubs with named owners: productivity; provenance's deferred cell-set remainder — partial OVERLAP, `{A,B}` vs `{B,C}` meeting at `{B}` as an inferred incorporate (the poset round; plain containment now lands in `Context`). |
| 2 complete | `Complete.res` | **the sibling-opens completion landed at any rank** — `harvest` → `solve` → `realise` bodies real for the k≥2 lists time-travel gap: `harvest` finds a value spanning k incomparable list siblings (pairwise mutually invariant, **fully uncrossed** — no axis of the combine appears in any constructed product), reading the FULL span off `Annotate.valueAxes` (so it reaches every axis, not just the first incomparable pair the linear raise names) and demands a `MustCross(flows)`; the siblings need not be TOP-LEVEL — a combine inside an enclosing loop names that loop's axis in its span as well, and what gets crossed is the span's **sibling frontier** (`frontier`: the axes that do not determine another axis in the span), so the per-group product completes with the loop's axis dropped as shared context and the inserted product living one layer in. The guard is that every dropped axis be shared by EVERY frontier member: an ancestor of some but not all of them (one axis top-level, the other inside a loop) is a real ambiguity about which nesting to commit and stays a witness (Main 10e/10f); `solve` dedups by the axis SET; `realise` mints a root-unreachable product — a single `Cross` for k=2, a left-nested `Cross(Cross(x,y),z)` chain for k≥3 — into the node set, reporting one insertion per product (each carrying the ids of the nodes it minted, which is what the `+`-line lens points at). The product's stored ORIENTATION comes from the combine's own operand order (the structural `valueAxes` walk) — a fact about the wiring, not about node ids, which is what makes the lens re-derivable after a print/reparse round (Main 10d). Runs **before** Check (Pipeline), which validates the *completed* program — the inserted product gives the combine a home, so it compiles via the whole-table (cube) emitter at any rank instead of witnessing. Identity for already-committed programs, and the "fully uncrossed" guard leaves an under-covered consumer (a combine whose axes are entangled with a partial/overlapping product — Main 15f/15g) a witness, so every other witness is unchanged. Still ahead: dependent-nesting Nests edges, commute-chain lifts, the canonical heuristic table. |
| 3 annotate | `Annotate.res` | write index + species + **flow-variable sets** (`introducedAxes`/`sourceAxes`/`valueAxes` and the `crossViolation` mutual-invariance demand — the invariance fact, pure structural non-merging walks) implemented; `crossViolation` has two cells, and they say different things: source-vs-introduced rejects a **dependent nesting** (the doc's third filtering regime), and introduced-vs-introduced rejects a **repeated axis** — one axis reached through both operands, `Poset.res`'s repeated-flow diamond, which is not two axes at all (Main 15r4); the walks themselves now live in `Context` (they return flow refs there, which the collect-remainder context report needs) and these are their key-set views. Caching the sets in the annotations record and the deferred placement/strictness/consumer-set annotations have their slot reserved. |
| 4 codegen | `Codegen.res` | **machinery real and running**: pure let-floating placement, (node, port, context) memo with prefix reuse, thunk-tagged context instantiation, flow spines. Emitters done: Lit, App (fn as a wire — computed functions work), iter collect (list/option chains with Join, any-list rule), **case collect** (exhaustive if-chain, else-throw — now over **cell sets**: a branch may be a partial collect's merged flow, so the design's covering HTTP collect is this emitter, with the pair's arm-per-cell each binding the merged value via `memoiseMergedValues`, the containment theorem read operationally), **the cell chain** (`emitCellChain`/`buildChain` — ONE emitter for every join chain that dispatches somewhere, the filter and the partial collect having turned out to be the same construct at two widths: iter levels (list / option loops) and dispatch levels (a case-alt keeps one cell, a partial keeps k, one arm each) interleaved in ANY order and at any position. The walk is RECURSIVE because a partial level BRANCHES — every level after it, and the payload, is assembled once per covered cell under that cell's own context — which is what makes a non-trailing partial (`join(join(list, partial), inner-list)`, "for each error firing, iterate its details") work, the multi-cell twin of filter-then-flatmap. Each arm additionally binds every merged value on the path down to its cell (`memoiseMergedValues`), so **computation AT the merged context** — the doc's `logAndFallback` step — compiles: `matchChain` matches a bundle step by cell containment, so a value whose context is `{A,B}` is available inside each arm, emitted once per arm and evaluated once per firing, `partial-collect-design.md`'s own "code duplicated, evaluation still once". The any-list rule decides the accumulator, so all three of the doc's terminations — join-absorbed filter, collected alone, covering — differ only in that and in who owns the arms), **registers** (the Delay pair: mutable accumulator over an iter driving flow — a single uncollect OR a **flattened (joined) sequence**, e.g. a running sum over a list-of-lists: the levels nest as loops and the ONE accumulator lives outside them all, folding the whole flattened firing order; `prev` aligns with the innermost element because a joined driving flow places it at the join's interior — the fork "dissolves on sequences", `delay-ontology-design.md`; the driving flow may also be **filtered** — `join(list, case-alt)` folds the Some-subsequence, `reg` advancing only on kept firings, `delay-ontology-design.md` route (b) — or **partial**, a merged flow of k cells, which is the same construct at width k: the whole skeleton is the shared recursive `buildChain`, so a partial level branches into k arms each carrying its own copy of the step subtree (exactly one runs per firing, the merged value resolving in each arm by containment) while the ONE accumulator stays outside every loop, guard, and arm; and the driving flow may be ONE AXIS OF A PRODUCT with the step spanning the product — a **fibered register**, "reduce along an axis, fibered over the rest": the loop is emitted inside the holding loop and folds each fiber independently, `final` a flow of rank n−1 rather than a scalar, which is just the ordinary register with the other axis as its surrounding context), **the running view (scanl)** (a sibling collect over the register's OWN driving flow reading `prev` — `emitRunningCollect`: the eager model gives each consumer its own loop, so the reading collect just re-runs the fold and PUSHES the running value each firing instead of only returning the final accumulator; collecting `prev` gives the prefix values BEFORE each element, collecting the stepped value gives them AFTER; the write half's `final` still folds independently in its own loop; one or many registers over that same flow, `delay-ontology-design.md` "a register is a feature of the flow"; the driving flow may be a plain iter chain, a **filtered** one, or a **partial (cell-set)** one — the view walks the levels through the same shared `buildChain` the register's own fold walks, so both the push and the advance sit inside the guard (or, at width k, inside the arm that fired) and the view is the scan of the KEPT subsequence, one element per kept firing; `levelKey` names a partial level by its CELL SET, which is what stops a view over `{A, B}` being offered the register that folds `{A, C}` — and over a **fibered** register too: the view is placed at the fiber its register folds over, read off the write half, so a scan along one axis of a product keeps the FULL product shape while `final` drops the folded axis, `product-flows-design.md` "The running view keeps the shape"), **cross, whole-table (any rank, at any depth)** (the product of **n** list axes — a binary two-axis product OR a rank-3+ cube authored by nesting binary Crosses, `cross(cross(x,y),z)`: one shared point-indexed table/cube built once in the Cross's stored orientation, all k! collect orders indexing it — every transpose/permutation is free, the user's computation runs once per point; `product-flows-design.md`'s "Compile" / "smallest first step" 2 and its N-ary section, "the table indexing generalises verbatim"). The axes need not be TOP-LEVEL: a product carries its own `exterior` — the common context of its axes, which is `Context.flowContext` of the Cross, empty for a top-level product and the enclosing chain for one opened inside a loop — and the table is built once per point of it, its feeds compiling there, `tableMemo` context-keyed by the same prefix rule the ordinary memo uses. The one genuinely new rule is `spansProduct`: a product-spanning value varies over every axis of the product and over nothing else except the axes of its exterior, which are coordinates of WHICH table this is rather than of a point within it. `productAxisOf` stops asking about nesting because nesting is not its question — two axes that nest inside each other are a dependent nesting, which Check's `invariance` rule witnesses first). **A product axis may be a FILTERED one** — a join chain `join(list, case-alt)` rather than a single open, `product-flows-design.md`'s first filtering regime ("filter an axis by its own element … still a product, still crossable, still transposable. Rectangular, just smaller"). The table build stopped writing its own loops for this: every axis is now walked by the shared `buildChain`, so a plain open is one for-of and a filtered axis is its own chain of loops and guards contributing one row per KEPT firing, with `sVal` compiling at the innermost context either way. What a consumer needs of an axis is only its EXTENT, because it traverses by index — an array's `length` for a plain open, and for a filtered one the count of kept firings, walked once by `getOrBuildExtent` (the same chain, with `c++` for a payload) and shared at the product's exterior, so build and traversal agree on the coordinates by construction. Both orders still read the one table and the user's computation still runs once per point. The leading layer must be a list (it is the extent); everything after it only decides which firings survive. A predicate reading the OTHER axis's element is the design's THIRD regime and is not an axis at all — it makes the operands dependent, and Check's `invariance` rule witnesses it), **the fibered (partial) product traversal** (a chain collecting only SOME of a product's axes, the rest HELD by enclosing loops — "reduce along an axis, fibered over the rest", `product-flows-design.md`: `matchPartialProductChain` + the shared `emitTableTraversal`, which the full chain now routes through too. A product axis is traversed by INDEX wherever it is iterated — `seg` carries the loop's `idxVar` — so a traversal nested inside a holding loop indexes the one shared table at the held coordinate; the user's computation still runs once per point, and both fiberings of a rank-2 product read the same table, and a collect is now PLACED by its own `Context.valueContext` report rather than by its flow's exterior, which is the same thing for every non-fibered collect and the fiber for a fibered one. Supported at ANY fiber width — a rank-3 product collected over one axis holds `{Y, Z}`, and the traversal indexes the one shared cube at both held coordinates; what places its consumers inside both holding loops is `Context.remainderPath` naming both surviving axes plus `matchChain` matching them set-wise), **the transposing commute** (a `Commute` over a CROSSED pair, `product-flows-design.md` theorem 2 / `lazy-stream-commute-design.md`'s "Transpose" row: transpose is a RE-READING, not a restructuring, so a commute output port simply DENOTES its operand swapped — `Context.throughCommutes` — and the transposed chain becomes an ordinary product chain in its own order. No emitter was written: every k! order already indexes the one shared table, so the transpose costs nothing and the user's computation still runs once per point (Main 15p's add-once golden). The gate is at the call site — only the product matchers resolve, and they then require the resolved flows to be axes of one constructed product — so a commute over a genuine nesting, the directed SEQUENCE operation, declines exactly as before. At rank ≥ 3 the swapped pair need not be neighbours in the stored orientation: a product has no "between"). An **under-covered** n-ary consumer now splits two ways: the case where **no product spans the combine's axes at all** (e.g. `f(x,y,z)` with only `{X,Y}` crossed) is witnessed by Check's full-span alignment before codegen runs; a fiber of any width compiles. The `underCoveredProduct` backstop remains for the shapes neither matcher recognises (a chain whose terminal has no linear context and whose held axes are open with no coordinate), declining with a clean `Todo` rather than crashing — gated now on the chain's head being a product axis at all, since a collect over an ORDINARY flow whose branch value spans a product is not an under-covered table read but the enclosing loop OF one. `Todo`/deferred, each citing its design doc: commute over a NON-product nesting (the sequence operation — option out of a stream, short-circuiting — whose output construction waits on stream flows; the transposing commute compiles, above); cross of non-list axes (`product-flows-design.md` open question 6 — `cross(list, option)` is not yet asked for, and stream/async/incremental axes wait on their kinds' own rounds); (the FIBERED read over a **chain** axis — filtered or flattened — is closed: holding an axis means having its coordinate, and a chain axis's coordinate is the running count of the firings it produces, so the holding chain mints a kept-firing counter and hands each firing `const i = c++`, tagged onto its innermost segment as that segment's `idxVar` — the same `seg` slot a plain axis's loop index fills, so the traversal reads it unchanged); (the partial collect's **cell-set** row is closed — the merged-context computation, the covering cell-set collect, a partial built over another partial, a non-trailing partial level, the on-demand read from inside a cell, and the overlap meet all compile; and the cell-set world is closed everywhere else too — a register over a partial merged driving flow and its running view both compile); a register over the **whole product** (a grid — "reduce the whole product as one sequence") is no longer a codegen gap at all: it is ill-formed for the ordinary reason (no order exists) and Check's `order-demand` rule now witnesses it before codegen runs, remedy "fold one axis, or Join first"; a **product running view** (a sibling `prev`-read over a cross driving flow the collect does not directly scan — the poset remainder of the shared-loop-skeleton case, which `emitRunningCollect` guards out with a clean `Todo`; the *filtered*, *partial*, and *fibered* running views all compile). The `DelayRead` arm of `compileValue` now `Todo`s (not `failwith`s) when `prev` reaches it: a well-formed boundary `prev` is witnessed by Check's flow-borne rule, so a memo miss there is always a deferred running-view gap, not a compiler bug. |
| runtime | `Runtime.res` | the emitted prelude (the three lazy helpers) + builders. Grows the stream/async cells later; owns the inline-vs-imported packaging question. |
| entry | `Pipeline.res` | derive → complete → check → annotate → codegen → `JsPrint`. Witnesses come back as data (`result`); a not-yet-written emitter raises `Codegen.Todo` (a compiler gap, surfaced to the caller). Also `completionText` — the **completion lens**: derive + complete + print with the inserted operators faint (`+` lines). No checking, so a program that will not compile can still be seen with its inferred structure. |

The text surface (`textual-representation-design.md`):

| module | status | what it is |
|---|---|---|
| `TextAst.res` | working | Surface statement AST — the meeting point of both directions. Grammar-as-implemented is documented in its header. |
| `TextLex.res` | working | Line-oriented lexer; sorted arrows (`->`/`~>`/`-~>`), sigils; indentation never parsed. |
| `TextParse.res` | working (v0 subset) | tokens → TextAst. Owns only the lexically decidable; pointed errors for not-yet-parsed forms (lanes). `+` lines are skipped (derived, never stored). **Struct stages parse**: `aggregate f1, f2` (the chain's sources, in order, are the field values — the same several-sources-one-stage shape an application uses) and `disaggregate f1, f2` (the chain's topic is the struct; the stage binds the NODE, whose fields project off that name). |
| `TextResolve.res` | working (v0 subset) | TextAst → `Program` via `Build`. Pronouns desugar here (P8): single-assignment global names, ordinal taps, the implicit flow stack as chain-local state. No semantic checks — those stay in `Check`, shared with every authoring path. A Disaggregate binds an `EStruct` env entry, so `d.field` resolves through the same `TProj` arm a case split's `cs.<Alt>` does; an `out` declaration's source may be a projection too (`out x = d.field`), which it could not be before. |
| `TextPrint.res` | working (total + chains) | `Program` → text. Total — genuinely so as of the struct round: registers, commute, cross, and now **Aggregate / Disaggregate** print (the last `failwith` in the printer is gone). A Disaggregate joins the case split and the commute as a node NAMED once whose ports print as projections (`namedAsNode`, prefix `d`), so the printer's existing machinery rendered it with nothing new. First pretty round DONE: single-consumer runs fuse into postfix chains, implicit flows drop their `~name`, single-use data literals inline, statements are topologically ordered by name dependency. **`+` completion lines DONE**: `print(~inserted, p)` prefixes the statements a completion minted with `+`, the textual analogue of the editor's faint rendering — reached through `Pipeline.completionText`. Parse already discards `+` lines, so the lens reparses to the AUTHORED program and re-derives identically (conservativity / determinism / idempotence, Main 10d). Still deferred: junction taps (named fan-out stands in), bare `join` in a chain (joins print standalone), derived indentation and the span lint. |

`Main.res` (`npm start`) is the smoke suite / playground: text and
handles building identical wiring, eval'd results validated against
author-written expected values, round-trips, witness demos, and
programs that print and check but decline to compile (the poset-round
gaps). Currently 300 checks.

## The single engine

Pass 4 is `Codegen.res`. An emitter that is not written yet raises
`Codegen.Todo(msg)` — strictly for gaps (`failwith` remains reserved for
compiler bugs and ill-formed programs Check should have witnessed).
`Pipeline.compile` surfaces a `Todo` to its caller; the smoke suite
(`Main.res`) either compiles a program and validates its eval'd value
against an author-written expected, or asserts that a poset-round program
declines with a clean `Todo`.

Until 2026-07, codegen ran beside a disposable bridge into an earlier
lazy compiler (`Expr`/`Compile`/`ExprPrint`), with `Pipeline.compile`
falling back to it on `Todo` and a differential check proving the two
engines agreed wherever both compiled. That migration is done: the bridge
and the earlier modules are deleted, the emitters that were validated
differentially now stand on the suite's independent oracles, and the
shapes that only the bridge could never express (a partial collect, a
register, a Cross) are validated against hand-computed values.

## What runs today

```
text ──TextLex/Parse──> TextAst ──TextResolve──> Program (node set)
                                       │
Build handles ─────────────────────────┤
                                       ▼
        Derive(id) ─> Complete ─> Check ─> Annotate ─> Codegen.res
                                                            │
                                                            ▼
                                                  JsPrint ─> eval
```

What compiles today: the value fragment (including **computed
functions** — App's fn is a wire, so it can be another node's output,
and **structs** — Aggregate emits an object literal, Disaggregate a
field access, each a memoised lazy cell let-floated exactly like an App,
so a per-element struct floats into its loop body),
list/option chains with binary Join, multi-close, single-module
multi-output compilation (outputs share one memo), **case collects**,
**filters** (join with a case-alt inner operand, including nested
flatten-then-filter — a Join whose outer is itself a Join stacks its
leading list levels before the dispatch — and **option leading levels**,
where a `join(join(list, option), case-alt)` loops the list, skips the
absent option per firing, and pushes the kept alt; an **all-option
filter** `join(option, case-alt)` has no list, so the any-list rule
makes its output an option — `let out;` set only when the option fires
and the alt matches; and a **non-trailing dispatch** — a filter-then-
flatmap `join(join(list, case-alt), inner-list)` that nests a for-of
inside the alt guard to flatten the kept alt's payload, a dispatch that
is not the innermost level), **partial collects**
(the direct slice — a merged flow of k covered cells feeding a filter or
an option, its leading levels list, option, or a case-alt dispatch — the
filter-then-partial `join(join(list, case-alt), partial)` — just like the
filter's; **and computation at the merged context**, the doc's
`logAndFallback` step: a value whose context is the merged cell set
`{A, B}` compiles inside each covered arm by the containment theorem
`{A} ⊆ {A, B}`, once per arm, evaluated once per firing), the
**covering cell-set collect** (branches keyed by disjoint covering cell
sets rather than single alts — the design's HTTP program end to end:
merge the two error cells, run one handler at the merged context,
reconverge with two singletons and a pair; coverage and the
disjointness demand both read off cell sets), a merged value **read
from inside one of its cells** by a chain that opened that cell some
other way (the containment theorem resolved on demand — inside cell A
the merged value IS A's branch value), values on **overlapping cell
sets** combining at their meet (`{A,B}` and `{B,C}` meet at `{B}`),
**nested cell merges**
(a partial collect built over another partial's merged flow — merge
`{ClientError, ServerError}`, then merge that with `{Redirect}` — with a
merged-context computation at each depth), a merged flow as a
**non-trailing level** (`join(join(list, partial), inner-list)` — keep the
error firings, then flatten a list derived from each, the multi-cell twin
of filter-then-flatmap),
**registers** (the Delay pair over an iter
driving flow — a single uncollect or a **flattened (joined) sequence**
(a running sum over a list-of-lists folds the whole flattened order with
one accumulator outside the nested loops), or a **filtered sequence**
(`join(list, case-alt)` folds the Some-subsequence, `reg` advancing only
on kept firings, `delay-ontology-design.md` route (b) — including the
filter-then-flatmap non-trailing dispatch), or a **partial (cell-set)
merged sequence** (the same filter at width k: the kept subsequence is the
firings landing in any covered cell, the k arms each carrying their own
copy of the step subtree with the merged value bound per arm, one
accumulator outside them all — Main 8l/8m) — validated against the design
docs and hand-computed
values), the **running view (scanl)** — a sibling collect over the
register's own driving flow reading `prev`, re-running the fold and
pushing the running value each firing (collect `prev` → prefix values
before each element, collect the stepped value → after; the write half's
`final` folds independently; one or many registers over the one flow;
Main 8h/8i, hand-validated) — over a **filtered** (case-alt) driving flow
too: the view walks the same levels the register's fold walks, so it is
the scan of the KEPT subsequence, one element per kept firing, both the
push and the advance inside the alt guard (Main 8j, and 8j2 over a
filter-then-flatmap driving flow) — and over a **partial** (cell-set)
merged driving flow, the same scan at width k, with the push and the
advance inside the arm that fired (Main 8j3; a view over a DIFFERENT cell
set of the same split is not offered that register's fold — Main 8j4) — a **fibered** running view
(a scan along one axis of a product, keeping the full product shape while
`final` drops the folded axis) now compiles, Main 15n — and the
**whole-table Cross of any rank** (a
product of n top-level list axes — the binary two-axis product consumed
by a two-collect chain in either order, and the rank-3 cube authored by
nesting binary Crosses `cross(cross(x,y),z)` consumed by a three-collect
chain in any order — one shared point-indexed table/cube, every order
indexing it, the user's computation run once per point; validated against
hand-built tables/cubes and a golden add-once
check. An axis need not be a single open: a **FILTERED axis** — the join
chain `join(list, case-alt)`, whose extent is the kept subsequence — is
crossable too, which is the first of `product-flows-design.md`'s three
filtering regimes ("filter an axis by its own element … still a product,
still crossable, still transposable. Rectangular, just smaller"). The
table is built by walking each axis's chain, one row per KEPT firing, and
a consumer traverses the axis by index over its kept COUNT — walked once
and shared — so both orders read the one table and the user's computation
still runs once per point (Main 15r, text- and handle-authored with an
add-once golden; Main 15r2 with BOTH axes filtered and a non-commutative
operator pinning the coordinates). A predicate that reads the OTHER
axis's element is the third regime instead: the operands are dependent,
no product exists, and Check's `invariance` rule witnesses it (Main
15r3) — as does an operand pair that repeats an axis (Main 15r4). A
chain axis may also be HELD rather than collected — the fibered read over
a filtered axis (Main 15r5) or a flattened one (Main 15r6, `join(list,
list)`): holding an axis means having its coordinate, and a chain axis's
coordinate is the running count of the firings it produces, which is the
order the table build pushed its rows in, so the holding chain mints a
kept-firing counter and hands each firing `const i = c++`. Whether a
dispatch dropped firings or a flatten multiplied them makes no
difference to the count, which is why the two are one rule at two
widths. An under-covered n-ary consumer, where no constructed product
spans the combine's axes at all, is now **witnessed as `time-travel` by
Check's full-span alignment** — `Context.posetValueContext` re-verifies
the whole value through the constructed products, so `f(x,y,z)` with only
`{X,Y}` crossed no longer admits on its first pair), the **fibered
(partial) product traversal** — "reduce along an axis, fibered over the
rest" (product-flows-design.md): a chain collecting only SOME of a
product's axes while enclosing loops HOLD the rest, e.g. collecting the
X axis of an `{X,Y}` product to get one column per y, reducing each
column, and gathering — both fiberings read the SAME shared table (the
holding loop is traversed by index and the traversal indexes the table at
that coordinate), so the user's computation still runs once per point;
validated against hand-computed per-fiber values with a non-commutative
reducer pinning the axis order, plus an add-once golden (Main 15h/15i).
The fiber may be **wider than one axis**: a rank-3 product collected over
one axis holds `{Y, Z}`, and both two-axis fiberings of one cube read
that one cube (Main 15j/15j2, hand-computed per fiber with a shared-cube
golden). What carries it is the context report naming every surviving
axis and `matchChain` reading a path's flows as a SET — sibling axes have
no order, and the consuming chain supplies the one it chose — and a
collect being placed by its own value report rather than by its flow's
exterior. A **register** may fold along one axis of a product too:
the loop is emitted inside the holding loops and folds each fiber
independently, `final` a flow of rank n−1 — or n−2 over a wider fiber
(Main 15k, both fiberings, hand-computed with a non-commutative operator;
Main 15j3 at rank 3), and
its running view scans each fiber while keeping the full product shape
(Main 15n). Reducing a product all the way down is two registers
composed — fold one axis, then fold the surviving flow — so the full
reduction is an **axis permutation**: the two orders agree for a
commutative operator and differ for a non-commutative one (Main 15o),
which is the doc's "one order-free exception" showing up as a test
rather than as machinery. A
register over the **whole product** is rejected **by the rule that owns it** —
Check's `order-demand` (Main 15m): the driving flow classifies as SURPLUS
order, so the Delay's demand for *one* previous firing has no answer, and the
witness names the remedy ("fold one axis, or Join the product first"). It was
already rejected before, but incidentally, through its step's combine. The
same rule's `Degenerate` cell is the other side of the coin: a register over a
**bare option** is admitted and compiles to the inert fold — seed when the
option is absent, one step when it fires (Main 8k) — because ≤1 firing is a
fact about cardinality, not about the kind. And the
**completion of a
sibling-opens time-travel program at any rank** — a k≥2 lists combine
with no hand-drawn Cross has the product spanning exactly its axes
inserted by `Complete` (which now runs *before* Check, so Check validates
the completed program): a single Cross for the two-lists case (Main 10),
a nested `Cross(Cross(x,y),z)` chain for a rank-3 combine (Main 10c),
then compiles via the whole-table (cube) emitter to the same values as
the hand-drawn form (product-flows-design.md's "smallest first step" 3
and N-ary) — and a per-group combine inside an enclosing loop as well
(Main 10e), where what gets crossed is the span's sibling FRONTIER, the
loop's own axis dropped as shared context; an ancestor shared by only
SOME frontier axes stays a witness, being a real which-nesting ambiguity
(Main 10f). A **product opened inside an enclosing loop** compiles the
same way the top-level one does, one layer in: the shared table is built
once per point of the product's exterior, both traversal orders read that
group's one table (add-once), a register folds one axis fibered over the
other with state crossing neither fibers nor groups, and a fibered
traversal reduces each column against a held coordinate that is itself
inside the enclosing loop (Main 15q/15q2/15q3/15q4). The **transposing commute** — a `Commute` over a crossed
pair, which `product-flows-design.md`'s theorem 2 makes total — now
compiles as well (Main 15p): its output ports denote its operands
swapped, so the transposed consumer is another permutation indexing the
one shared table, and the two axes count as nesting-adjacent because the
product makes them so (the join-adjacency carve-out). At rank 3 the
swapped pair need not be neighbours in the stored orientation, since a
product has no "between". Representable-but-not-compilable
(prints, checks, and now round-trips through the text surface): commute
over a genuine NESTING — the other operation the one word names, the
directed sequence with its short-circuit, waiting on stream flows
(its standalone `commute out of` form authorable in text — Main 15c),
a cross of NON-LIST axes (`product-flows-design.md` open question 6) or of
axes that are join chains rather than single opens (the rest of
the poset round; the flat rank-n product now compiles — 15d/15e,
its fibers at any width — 15h/15i, 15j/15j2/15j3, and a product opened
INSIDE an enclosing loop — 15q/15q2/15q3/15q4),
and explicit `in` nesting. A register over a **filtered** (case-alt)
driving flow now compiles (Main 8e–8g), and so does one over a **partial**
merged driving flow (Main 8l/8m); a register over a **product** driving
flow (a grid) is not a gap but a witness — Check's `order-demand` rule
(Main 15m).

## Decisions taken here (all cheap to revisit; recorded so they are
decisions, not accidents)

Representation and surface (from the first scaffolding round):

- **Node set from day one.** `Build.finish(b, ~outputs)`; no root
  expression anywhere. Forced by write halves; also the honest signature
  for multi-output diagrams.
- **Port-name scheme**: strings at the representation level; bare alt
  names on both sides, disambiguated by ref sort. (Ports doc open q.1 /
  text doc open q.6 — provisional.)
- **Join is flow-only** at the Expr level (confirmed lean, ports doc
  open q.3). Value crossings stay derived.
- **App fn and case discriminator are wires** (usually to `Lit` externs),
  not embedded JsAst — functions are values. The bridge requires them to
  resolve to Lits; Codegen does not (it forces the fn wire at the call).
- **`js "..."` externs** ride a new `JsAst.ERaw` (prints parenthesized,
  verbatim). The one additive change to the legacy layer.
- **Error surface**: witnesses as records `{nodeId, rule, message}`
  addressed to authored ids; pipeline returns them as data. Raising is
  reserved for compiler gaps/bugs.
- **Write half names its read by node reference** (not a thread port) —
  the recorded spelling question; either works, this is the smaller.
- **Text pipeline meets at TextAst**; resolve (not parse) owns names,
  taps, and the implicit flow stack, which is *chain-local resolver
  state* seeded from Context paths (the naturality note in the text doc).
- **Printer is total before it is pretty**; v0 emits the factored edge
  list (all named, forward), which reparses. Prettiness is a separate,
  focused round (implicitness thresholds, text doc open q.5).

Compile pipeline (this round):

- **`Codegen.Todo` (a not-yet-written emitter) vs `failwith` (a bug /
  should-have-been-witnessed) is a load-bearing distinction.** It was
  load-bearing during the bridge migration — a `Todo` fell back, a
  `failwith` never did, so a fallback that swallowed bugs could not let
  the two engines drift apart silently. The bridge is gone, but the
  distinction stays: `Todo` is a clean compiler gap surfaced to the
  caller, `failwith` is never reachable for a well-formed program.
- **Complete runs before Check; Check validates the completed program.**
  The pipeline is derive → **complete → check** → annotate → codegen (not
  derive → check → complete). Completion commits an under-determined
  program — inserting a Cross for a sibling-opens combine — and the
  committed form is what Check gates, so the inserted product turns a
  time-travel gap into a well-formed combine rather than a witness.
  Completion harvests its own demands (it does not read Check's
  witnesses — compile-strategy-design.md open question 6, "keep the
  outputs distinct"), and it is identity for already-committed programs,
  so every non-completable clash (bundle mixing, dependent nesting,
  coverage, flow-borne, invariance) is reported exactly as before. The
  alternative (check first, then complete) was rejected: it would either
  witness the very programs completion exists to fix, or require Check to
  special-case "completable" gaps it then leaves for a later pass.
- **Placement is let-floating, not buffers.** Every compile returns
  statements tagged with the context they must live in; owners (collect
  emitters, the top level) keep what is addressed to them and float the
  rest upward in their own results. Loop-invariant hoisting is the
  default behaviour of floating, not an analysis.
- **Context segments are thunk-tagged.** A codegen context is
  `array<{flow, thunkOf}>` — the structural flow path with each segment
  tagged by the collect whose emitted thunk owns that JS scope. Two
  sibling collects over one flow open structurally identical paths but
  distinct scopes; the tag is what stops a binding emitted inside one
  thunk from being memo-reused in the other (bodyRef object identity
  would do this imperatively; tags are the pure spelling).
  Consequence kept intentionally: per-iteration work still re-emits per
  consuming thunk — the documented cost of the eager model.
- **Memo keys on (node id, port); entries store the instantiated context
  the binding was placed in; lookup reuses on prefix** (the legacy
  `isAncestor` scan, re-plumbed). Lits memoise at the empty context. A
  structural required context (from `Context.res`) is *instantiated*
  against the current chain — as the **shortest prefix of the chain that
  opens every flow the path names** (`matchChain`), not as path equality.
  The chain may carry segments the path does not mention, which is what a
  product needs: a fibering axis is a sibling and so sits on no linear
  path, yet a value compiled inside a fibered traversal legitimately has
  it open. A flow the chain does not open at all still asserts, per
  check-and-tag; for an all-nesting program the path IS a prefix and this
  is the plain prefix rule it replaces (same for the level-adjacency
  assert, now `chainOpens`).
  Incomparable-context demands lift to a product context (point-indexed
  table) — that case arrives with the Cross emitter and must stay
  unreachable until the checker admits products.
- **Codegen state is a mutable map scoped to one invocation behind a
  pure interface** — the explicitly-allowed spelling in
  compile-strategy-design.md; `codegen` stays a function of
  (annotations, program).
- **The runtime lives in `Runtime.res`** as the emitted prelude.
  Packaging (inline prelude vs imported module) is deferred until streams make the
  prelude non-trivial; meanwhile Pipeline wraps one IIFE per output,
  each carrying the whole module's statements (unused lazies never run)
  — real ES-module packaging is compile-strategy open q.3.

## Fill-in worklist (each item small, suite kept green; written for
whoever picks this up next)

The tracks are independent — any order works. Most items below are DONE
and kept as a build log (they record how each emitter landed — some of
that history mentions the now-deleted bridge and its differential check,
the harness that validated emitters against an earlier compiler as they
were written; that migration is complete, see "The single engine"). The
live work is item 8, the poset round.

1. **Case collect emitter** — DONE (`Codegen.res`, `emitCaseCollect`,
   the `CaseFull` arm; spec: `Compile.emitCaseClose`). Pre-memoises the
   alt payload port (split id, alt name) at `exterior ++ [alt flow
   tagged with this collect]`; Main test 6 runs via NextCodegen and
   the differential validates it.
2. **Filter collect emitter** — DONE (`Codegen.res`,
   `emitFilterCollect`, the `hasAlt` arm of `IterCollect`; spec:
   `Compile.emitFilterClose`). Now a **unified level walk** over the
   spine (`filterPlan` = `FIter` | `FAlt`): iter levels (list for-of /
   option defined-check) and case-alt dispatch levels interleaved in
   **any order**, assembled innermost-out. Leading levels may be **list
   or option** (an absent option skips its firing, contributing nothing
   — mirrors `emitIterCollect`'s per-level for-of / if-defined branch;
   Main test 7e, beyond the bridge so hand-validated). The
   **all-option filter** (no list level) is handled too: the any-list
   rule (`lazy-compile-design.md`) makes its output an **option** (`let
   out;` + assign, set only when the option fires and the alt matches)
   rather than a list — the single-alt case of `emitPartialCollect`'s
   collected-alone reading (test 7c), so the two emitters stay
   consistent (Main test 7f, hand-validated). The **non-trailing
   dispatch** — an iter level nested *inside* a dispatch, i.e.
   `join(join(list, case-alt), inner-list)`, filter-then-flatmap: for
   each kept alt the emitter nests a for-of inside the alt guard's `if`,
   flattening the alt's payload list (Main test 7g, hand-validated —
   a shape the legacy filter close cannot express, its dispatch is always
   innermost). No `Todo` remains in `emitFilterCollect`. Flips test 7;
   differential validates the list-only trailing shapes.
3. **Parser catch-up** (`TextParse.res`): flow-ref lane groups — DONE
   for the labeled form (`~flow: value` lanes + `-~> collect =>` binder;
   `TextParse.parseLaneCollect` → `TextAst.LaneCollect` →
   `TextResolve.resolveLaneCollect` → `Build.collectCases`). Case
   collects now parse, compile, and round-trip (Main test 6b); the
   partial form's `~flow` remainder binder is wired but untested (needs
   the partial-collect emitter). **`cross with` DONE** — the standalone
   product statement (`~left ~> cross with ~right => ~flow`,
   `TextParse.parseStage`'s `cross` case → `TextAst.StCross` →
   `TextResolve`'s flow-source combine, mirroring `join into`) parses,
   resolves, compiles (via the whole-table emitter), and round-trips
   (Main 15b, both collect orders authored in text). **Infix
   operators DONE** — `+ - * / %` parse as accepted input (source infix
   `a * b` and the chain-position operator section `-> * 2`), desugaring
   to an App of the operator's extern (`TextParse.opInfo` precedence
   climb + `StBinop`; `TextResolve.opToJs`). The double/triple test
   stand-ins are now real inline multiplication (Main 2–6b). The
   canonical printer does not yet re-emit infix (design open question
   5), so a round-trip prints the desugared App form. **Prefix
   application DONE** — `f(x, y)` (and nested / curried `f(x)(y)`, and
   mixed with infix `f(x) * 2`) parses as a term via `TextAst.TApp` /
   `TextParse.parseApplied` / `TextResolve`'s `TApp` arm, building the
   same App the postfix stage `x, y -> f` does (the permissive grammar's
   other authoring path converging on one reading). The canonical printer
   emits the postfix form, so a round-trip prints `x, y -> f` (Main
   1c, with a prefix≡postfix wiring-identity check). **`commute out of`
   DONE** — the standalone swap statement (`~inner ~> commute out of
   ~outer => cN`, `TextParse.parseStage`'s `commute` case gaining the
   optional `out of ~outer` clause → `TextAst.StCommute({outOf})` →
   `TextResolve`'s flow-source combine, mirroring `join into`) parses,
   resolves, and round-trips; the two-port Commute node binds by name
   (`ECommute`) so its swapped flows resolve as `~cN.outer` / `~cN.inner`
   (a case split's `~cN.<Alt>` projection generalized). Bare `commute`
   stays the chain-position swap of the two innermost open layers.
   Commute is still representable-but-not-compilable (the emitter is the
   poset round's), so Main 15c validates by wiring identity, a clean
   check, and the round-trip, not by evaluation. Still ahead of the
   parser: fused lanes, `;` multi-resume. Each remaining form has a
   pointed "not yet parsed" error today.
4. **Printer round** (`TextPrint.res`): chain compression — DONE
   (single-consumer runs fuse into postfix `->`/`-~>` chains; a flow a
   chain opens *and* closes is implicit — no `~name`, the bare `collect`
   reseeds the stack from the value's context; single-use data literals
   inline at their use site; the App-fn / split-disc / output positions
   keep their operand named). The subtle piece is ORDERING: fusing a
   chain onto its head prints it at the head's slot, so a `-~> collect
   ~jN` or a referenced fn literal can end up before the statement that
   binds it — statements are therefore topologically sorted by name
   dependency (a "unit" = head node + the nodes it fuses; edges from any
   cross-unit input; Kahn, ties by node order). Main has golden
   assertions (`expectFusedLine`) beside the round-trips. Still deferred
   (kept out to keep the round focused): junction TAPS (`|`) — named
   fan-out is the total, round-tripping stand-in; bare `join` in a chain
   (joins print as the standalone `join into` form); derived indentation
   by flow depth and the span lint. **`+` completion lines DONE** —
   `print(~inserted, p)` marks the statements a completion minted with a
   leading `+`, the textual analogue of the editor's faint rendering
   (`time-travel-programs-design.md`, "faint is a leading `+`");
   `Pipeline.completionText` is the lens (derive + complete + print, no
   checking, so an uncompilable program can still be seen with its inferred
   structure). Three properties fall out of machinery that already existed
   rather than being arranged for: the topological statement sort places the
   inserted operator after the statements binding its operands (the doc's
   "reordering statements as needed to restore token-order-is-time"),
   `TextParse` already skips `+` lines so reparsing the lens returns the
   AUTHORED program (conservativity), and re-deriving from that reparse
   reproduces the same text (determinism/idempotence). Writing the third
   assertion is what caught a real bug in `Complete.harvest`: the inserted
   product's orientation was taken from flow keys, i.e. from NODE IDS, which
   a reparse renumbers — so the operand order flipped on re-derivation. The
   orientation now comes from the combine's own operand order (the structural
   `valueAxes` walk), which is a fact about the wiring; the flow-key sort
   survives only as `solve`'s dedup key, where order genuinely must not
   matter. Main 10d.
5. **Checks** (`Check.res`): **coverage** — DONE (`checkCoverage`):
   mixed-split / non-alt-multi-branch collects (via `classifyCollect`)
   plus duplicate-alt coverage, turning a case-emitter crash into a
   witness (Main test 11). **productivity** — unreachable today (the
   object graph is a DAG by construction; the only cycle is the register
   pairing itself), so left stubbed with that rationale recorded; it
   becomes load-bearing once a representation admits foreign cycles.
   **provenance's mixing-vs-time-travel classification** — DONE, folded
   into `checkAlignment` (bundle-provenance-design.md, "the same check
   with the property refined"): `Context.Incomparable` now carries the
   two flow *paths*, and `classifyClash` walks them to their first
   divergent step — sibling cells of one case split ⇒ `bundle-mixing`
   (hard error, names the split and both cells), otherwise ⇒
   `time-travel` (completable — completion inserts a Cross). Main
   tests 10 (`time-travel`) and 10b (`bundle-mixing`). `checkProvenance`
   now carries only the deferred cell-set / subset-lattice remainder
   (the poset round, item 8), where the not-≤ branch splits by the MEET:
   a non-empty meet (`{A,B}` vs `{B,C}` ⇒ `{B}`) is an inferred
   incorporate, not a clash — only a disjoint meet is bundle mixing
   (bundle-provenance-design.md, "Revision: overlap is incorporate, not
   a clash"). **flow-borne's general interior rule** —
   DONE (`checkFlowBorne` + `branchInterior`): a collect branch whose
   value is borne on a flow the collect does not iterate (a sibling
   alt's payload, an unrelated open's element) is now a witness rather
   than Codegen's "flow-borne port reached outside its flow" failwith —
   exact for element / alt-payload interiors (the branch flow targets an
   Uncollect), with Join/Commute/Cross interiors left to the poset round
   (`branchInterior` returns None). Main test 12. Remaining: none in
   this pass — these turned the remaining Codegen asserts into
   user-facing witnesses.
6. **Registers** — DONE for the self-driven case (`Codegen.res`,
   `emitRegister`, reached via the `DelayWrite` `final` port). The write
   half doubles as the feedback collect: it emits its own loop skeleton
   with a mutable accumulator (`let reg = force(init)`; `const prev =
   lazyDone(reg)` at body top; `reg = force(step)` at bottom; `return
   reg`). Main test 8's decline flipped to a real compile (running
   sum = 6, empty list = init). **Now also over a flattened (joined)
   sequence** (`emitRegister` walks `spine(flow)` as a nested iter-level
   chain — the same walk as `emitIterCollect` — and threads ONE
   accumulator declared outside all the loops, so a running sum over a
   list-of-lists folds the whole flattened firing order; `prev` aligns
   with the innermost element because `Context.valueContext(DelayRead)`
   now places `prev` at the driving flow's interior (`flowInterior`),
   which is unchanged for a single uncollect. The fork "dissolves on
   sequences" — `delay-ontology-design.md`; Main 8c/8d, 8d the
   per-group contrast). **Now also over a FILTERED (case-alt) driving
   flow** — a running sum over the kept subsequence (`join(list,
   case-alt)`): `emitRegister` walks the spine through `walkFilterLevels`
   (the iter/alt-guard walk factored out of `emitFilterCollect`), so the
   step and `prev` sit inside the alt guard and `reg` advances only on the
   firings whose alt matches — the Some-subsequence fold of
   `delay-ontology-design.md`'s route (b) "filter inside" ("the register
   only updates when the option is Some"). A non-trailing dispatch
   (filter-then-flatmap, `join(join(list, case-alt), inner-list)`) folds
   the flattened kept order (Main 8e/8f/8g). Remaining: (a) the **productivity
   check** (`Check.res` stub) — currently unreachable, since the object
   graph is a DAG by construction and the only cycle is the register
   pairing itself, so every buildable program is productive; it becomes
   load-bearing once a representation admits foreign cycles. (b) A
   register `prev` **read by a sibling collect** over the same flow —
   the **running view (scanl)** — DONE for the pure-iter case
   (`emitRunningCollect`, Main 8h/8i): the eager model gives each
   consumer its own loop, and the key realization is that no
   loop-*sharing* is needed — the reading collect just **re-runs the
   fold** and pushes the running value each firing, threading its own
   accumulator exactly as `emitRegister` does but returning the pushed
   list instead of `reg` (`delay-ontology-design.md`, "a register is a
   feature of the flow"). Collecting `prev` gives the prefix values
   BEFORE each element ([0,1,3] for [1,2,3]); collecting the stepped
   value gives them AFTER ([1,3,6]); the write half's `final` folds
   independently in its own loop, and the list source / init / operator
   feeds memoise once and are shared by all the loops. One or many
   registers over that one flow are handled (each gets its own
   accumulator, all `prev` decls at the innermost body top, all
   advances after the push). The routing is a `readsPrevRegs` check in
   `emitCollect`'s IterCollect arm; the register's step is found via
   `st.ann.writeIndex`. The **filtered (case-alt)** running view is now
   DONE too (Main 8j/8j2): the view walks its levels through
   `walkFilterLevels`, the same iter-loop / alt-guard walk the register's
   own fold walks (item (c) below) and the filter collect uses — so the
   two halves agree on which firings are kept by construction, the push
   and the advance both sit inside the alt guard, and the view is the
   scan of the KEPT subsequence: one element per kept firing
   (filter-then-scan). A dropped firing contributes nothing to the view
   and does not step the register. `levelNodeId` became `levelKey` in the
   same change — an alt level carries its ALT NAME as well as its split
   id, so "does this register scan the same sequence I iterate?" can no
   longer be answered yes for two *different* alts of one split. The
   **PARTIAL (cell-set)** running view is DONE as well (Main 8j3), and it
   is the same sentence one width out: the view assembles through
   `buildChain` too, so a partial level branches and each arm carries its
   own push and advance, and `levelKey` names a partial level by its CELL
   SET — the alt-name refinement generalised, so a view over `{A, B}` is
   not offered the register that folds `{A, C}` (Main 8j4). The assembly
   loop `emitRunningCollect` had duplicated from `emitRegister` went with
   it; what remains is the `mkPayload` (the `prev` decls, the push, the
   advances), which claims the statements addressed to its own context so
   the `prev` decls stay ahead of everything reading them. Still deferred
   (guarded out with a clean `Todo`): a **product** running view — a
   `prev`-read over a flow with cross levels the collect does not directly
   scan (the poset round; the *fibered* view compiles, Main 15n). The
   `DelayRead` arm of `compileValue` now raises `Todo` rather than
   `failwith` for any `prev` that reaches it (a boundary `prev` is
   already a Check flow-borne witness, so a memo miss there is always a
   deferred running-view gap, never a bug — the error-discipline fix).
   (c) A register over a **filtered
   (case-alt) driving flow** — DONE: `join(list, case-alt)` folds the
   **Some-subsequence**, `reg` advancing only on the kept firings
   (`delay-ontology-design.md` route (b), "filter inside"). `emitRegister`
   now walks the spine through `walkFilterLevels` — the same iter/alt-guard
   walk `emitFilterCollect` uses — so the accumulator step and `prev` sit
   INSIDE the alt guard and the one `let reg` lives outside every loop and
   guard; a non-trailing dispatch (filter-then-flatmap, `join(join(list,
   case-alt), inner-list)`) folds the flattened kept order (Main 8e/8f/8g).
   (d) A register over a **PARTIAL merged driving flow** — DONE (Main
   8l/8m), and it needed no new machinery either, only the walk stated one
   width more honestly. A partial level is a dispatch that keeps k cells
   where an alt level keeps one, and `OrderDemand.orderOf` already reads a
   merged flow's order as "the parent's, restricted" — so the kept
   subsequence is "the firings landing in any covered cell" and the fold is
   the filtered register at width k. `emitRegister` now assembles through
   **`buildChain`**, the recursive level walk `emitCellChain` uses, with an
   `mkPayload` that emits `prev`, the step subtree, and the advance at each
   innermost context the chain reaches: a partial level BRANCHES, so each
   covered cell gets its own copy of the step subtree (exactly one arm runs
   per firing, and the merged value binds per arm by `memoiseMergedValues`),
   while the ONE `let reg` stays outside every loop, guard, and arm. The
   payload claims the statements addressed to its own context rather than
   floating them into the level's bucket, which is what keeps `prev`
   declared ahead of the step bindings that read it — the one ordering fact
   the hand-rolled assembly had encoded as a "head". The non-partial path is
   the same code with zero branches, so the emitter lost its duplicate
   assembly loop in the bargain. Still Todo: a register over a **product**
   (a grid) is not an emitter gap — it is ill-formed for the ordinary
   reason, witnessed by Check's `order-demand` rule (Main 15m).
7. **Retirement** — DONE (2026-07). No reachable smoke program fell back
   to the bridge, so the bridge, the `Pipeline` fallback, and the earlier
   modules (`Expr`/`Compile`/`ExprPrint` and the old `Main`) were deleted,
   the gap tests from the earlier value suite ported into the smoke suite
   first (Codegen compiles all of them), and `src/next/` moved up to
   `src/`. Codegen is now the only engine.
8. **The poset round** (deferred together, because they are one
   context-model generalization — linear prefix → a genuine poset with
   non-tree segments). **Front half started**: Cross's "smallest first
   step" 1 — the **invariance fact** — is DONE (`Annotate.res` flow-
   variable sets: `introducedAxes`/`sourceAxes`/`valueAxes`; `Check.res`
   `checkCross`, rule `invariance`; Main test 13). Pure non-merging
   walks, so the demand is answerable on the two *incomparable* flows a
   Cross combines — the one fact the linear context model can't supply.
   A dependent nesting (inner source varies with the outer element) is
   witnessed; top-level siblings and siblings that share an outer loop
   both pass (the demand tests source-vs-own-axis, not raw set overlap).
   **Context representation started**: the context model is a **series-
   parallel poset** (`Poset.res`), settled on paper (recorded in the
   session's Fork-A discussion) — nesting = SERIES, Cross = PARALLEL, so
   every well-formed context is SP; the non-SP "N" is always a
   repeated-flow diamond (align-vs-cross, i.e. zip-vs-Cross, left
   unresolved) and is witnessed, never represented, which makes SP the
   *complete* model rather than a convenient restriction. The `≤`
   primitive (`axes-⊆ + order-extends`) and the LUB `merge` (least
   *constructed* product above two siblings, else `Incomparable`) are
   implemented and unit-tested (Main test 14). **First wiring
   landed**: `Context.productsIndex` builds the product index from the
   program's Cross nodes (`crossProduct` = `Poset.parallel` of the two
   operands' full contexts, via `fullPoset` — which **recurses into a
   nested Cross operand** so `cross(cross(x,y),z)` flattens to a flat
   `{X||Y||Z}` rather than an opaque axis), and `checkAlignment` now
   consults `Poset.merge` so a valid sibling Cross ADMITS its combine
   while a wrong-axes / missing / bundle-mixing clash still witnesses
   (Main test 13b). **The whole-table emitter landed at ANY rank**
   (Cross's "smallest first step" 2, then the N-ary section): `Codegen.res`
   `emitProductChain` / `getOrBuildTable` compiles the product of **n**
   top-level list axes consumed by a **k-collect** chain — one shared
   point-indexed table/cube built once in the Cross's stored orientation
   (n nested index-based loops, `cForArr`, assembled innermost-out), every
   collect order indexing the same `force(table)[i][j][…]`, so all k!
   permutations are free and the user's computation runs once per point
   (`product-flows-design.md`'s "Compile" and N-ary, "the table indexing
   generalises verbatim … more indices"; Main tests 15 (binary) and
   15d/15e (rank-3, handle- and text-authored), each with a golden
   add-once check and hand-built expected tables/cubes — beyond the
   bridge). The routing is `matchProductChain` (unwinds a k-deep
   single-branch collect chain via `chainFlows` and finds the product
   whose axes are EXACTLY the chain's axes, with `s` spanning all of
   them); `productOf`/`productAxesOf` flatten nested Crosses into flat
   axis sets, so a two-of-three-axis inner cross is also a product in its
   own right (the author naming a sub-product). Non-product programs are
   untouched, and a product value's App — whose args are on incomparable
   sibling axes, so `Context.valueContext` raises `Incomparable` — is
   placed at the current (product) context rather than asserting. An
   **under-covered** consumer splits into two shapes. Where **no
   constructed product spans the combine's axes at all** (a wrong-axes or
   sub-product-only cross under an n-ary combine), **checkAlignment now
   witnesses it** as `time-travel`: `Context.posetValueContext` recomputes
   a value port's context poset-aware — merging sibling axes through the
   constructed products (`Poset.merge`) instead of the linear prefix rule
   that stops at the first pair — so the full span is re-verified and the
   uncovered step raises `Poset.Incomparable` (Main 15f/15g; the doc's "no
   least upper bound ⇒ no context to combine at", including two overlapping
   sub-products with no common superset). **The fibered (partial) product
   traversal now COMPILES, at a fiber of any width** — "reduce along an axis,
   fibered over the rest" (`product-flows-design.md`, Registers over
   products; Main 15h/15i). Three pieces landed together, and they are the
   first real bite of the context report: (i) `Context` gained
   `collectRemainderFlows` — the axes a collect branch's value varies over
   that the branch's flow neither iterates nor sources — and
   `remainderPath` reports **the surviving axes** for such a collect
   ("a collect over a crossed axis reports `{Y}`"), which is what places
   its consumers inside the holding loops instead of at the top level; the
   flow-variable walks moved into `Context` (returning flow *refs*) to
   make that nameable, `Annotate` keeping the key-set views. (ii) A
   product axis is traversed by **index** wherever it is iterated (`seg`
   carries the loop's `idxVar`), so a nested traversal can index the one
   shared table at the held coordinate. (iii) `matchPartialProductChain` +
   the shared `emitTableTraversal` (the full chain routes through it too)
   emit the read; both fiberings of a rank-2 product index the same table,
   so the user's computation still runs once per point. (iv) A **wider
   fiber** — a rank-3 product collected over one axis, holding `{Y, Z}` —
   works the same way, and needed only three small generalisations, each
   the rule stating itself more honestly: `remainderPath` reports EVERY
   surviving axis, flattened in the combine's own operand order; `matchChain`
   matches a structural path's flows as a SET, which is what "the shortest
   prefix of the chain that opens every flow the path names" always said
   (sibling axes have no order between them — the consuming chain supplies
   the one it chose, and ordered matching would reject a transposed reading
   for no reason but the flattening's arbitrary order); and a collect is
   placed by its own `Context.valueContext` report rather than by its flow's
   exterior — identical for every non-fibered collect, the fiber for a
   fibered one. `Check`'s flow-borne interior rule reads its containment as a
   set too, admitting a surviving axis that is CROSSED with one the collect
   iterates (held open by the enclosing traversal) while still witnessing an
   uncrossed sibling. Main 15j/15j2 (both fiberings of one cube, with a
   shared-cube golden) and 15j3 (the register at rank 3). The fiber carries
   the **register**
   form ("Registers over products", the finding: "for each fixed y, run an
   ordinary register along the X-fiber; state does not cross between
   different y's"): `Context.valueContext` reports the surviving axis for a
   `final` whose step spans a product, so `emitRegister` puts its loop
   inside the holding loops and folds each fiber independently, `final` a
   flow of rank n−1 — or n−2 over a two-axis fiber (Main 15k — both
   fiberings in one program, a non-commutative operator pinning the
   within-fiber order; Main 15j3 at rank 3). Which flow
   fixes the axis — the doc's open Delay-ontology question — does not
   arise here: the Delay names its driving flow, so the axis is the one it
   names. The doc's step 1, the **"no order" witness** for a register over
   the WHOLE product, is now DONE: `OrderDemand.orderOf` implements the
   kinds table as the structural provenance walk the design calls for
   (`delay-ontology-design.md`, "The kinds table, cashed"), and
   `Check.checkOrderDemand` turns its three failing cells into witnesses —
   the one reachable today being SURPLUS, the product's embarrassment of
   orders, whose message names the doc's remedy ("fold one axis, or Join the
   product first"). Main 15m asserts the rule by name; the step's-combine
   `time-travel` witness still fires alongside it, since a Cross output port
   is not yet an axis set in the poset. The rule's other side is that
   `Degenerate` order — a bare option or case alt, ≤1 firing — is ADMITTED,
   because inert is not ill-formed and ≤1 firing is a fact about
   cardinality, not about the kind (Main 8k pins the inert fold: seed when
   the option is absent, one step when it fires). Still owed on this row:
   the commutative-monoid exception, where the operator's own law discharges
   the order demand — it needs the catalog row's commutativity flag
   (`CollectFamily.res`). `instantiate` was
   generalised for this: the required context is the shortest prefix of the
   chain opening every flow the structural path names, so a value inside a
   fiber may report just `[X]` while the chain holds `[Y, X]`. The
   **running view** follows the register (`product-flows-design.md`, "The
   running view keeps the shape"): `emitRunningCollect` places itself at the
   fiber its registers fold over — read off the write half, since a
   `DelayRead` does not name its step — so a scan along one axis of a
   product keeps the FULL product shape while `final` drops the folded axis
   (Main 15n, `prev` for the values before each element and the stepped
   value for after). The two product matchers and the
   `underCoveredProduct` backstop now skip a terminal that reads `prev`: a
   running value is not a per-point function of the product (it depends on
   the fold so far along the register's axis), so it belongs to the
   register's loop, never to a table.
   **The NON-TOP-LEVEL product is DONE** — the per-group cartesian product,
   a Cross whose axes are opened inside an enclosing loop. Check had been
   ready for it since test 13b (`L > {X || Y}`, which `Poset` builds as
   series-prefix-then-parallel), so what was missing was only where the
   table lives. A `product` gained its `exterior` — the common context of
   its axes, `Context.flowContext` of the Cross — and the table is built
   there, one per point of it, with its feeds compiling there too and
   `tableMemo` context-keyed on the same prefix rule the ordinary memo
   uses. `productAxisOf` stopped asking about nesting, which was never its
   question: axes that nest inside each other are a dependent nesting,
   which Check's `invariance` rule witnesses first. The one new rule is
   `spansProduct` — a product-spanning value varies over every axis of the
   product and over nothing else except the axes of its exterior, which
   say WHICH table this is rather than which point within it — and the one
   new gate is on `underCoveredProduct`, which must not claim a collect
   over an ordinary flow whose branch value spans a product, that collect
   being the enclosing loop OF a table read rather than an under-covered
   one. Everything the top-level product had came along unchanged: both
   orders sharing the one per-group table, the fibered register, the
   fibered traversal (Main 15q/15q2/15q3/15q4). `Complete` followed
   (Main 10e/10f): a combine inside a loop names that loop's axis in its
   span, so completion crosses the span's sibling **frontier** — the axes
   that do not determine another axis in the span — with the guard that
   every dropped axis be shared by every frontier member.
   **A FILTERED axis is now crossable** — an axis may be a **join chain**
   (`join(list, case-alt)`) rather than a single open, which is the first
   of `product-flows-design.md`'s three filtering regimes, "filter an axis
   by its own element … the same rows survive for every x. Still a
   product, still crossable, still transposable. Rectangular, just
   smaller" (Main 15r/15r2). The blocker recorded here had been that such
   an axis "is not a single axis key in the flow-variable model", and that
   turned out to be the right diagnosis with a smaller cure than a
   poset-VALUED report: the model does not need the chain to BE one key,
   it needs both sides to name the same keys. `Context.flowLayers` reads a
   join chain as the sequence of layers it is, so `fullPoset` lifts the
   Cross operand to `(list > alt)` — exactly how a value borne on the axis
   reports itself — and the product `{(list > alt) || Y}` covers the
   combine; `productAxis` carries the axis's own layers as `spanKeys` for
   the same reason, while its identity for chain-matching stays the flow
   key the consumer's collect names. Writing that down exposed a real
   over-report next door, which is what had made the two sides disagree:
   `sourceAxisFlows` of a Join counted the axes the join INTRODUCES as
   also determining it, so a collect over `join(list, case-alt)` reported
   the list axis as SURVIVING the collect. In codegen the table build
   stopped writing its own loops and now walks every axis through the
   shared `buildChain`, so a filtered axis contributes one row per kept
   firing; a consumer needs only the axis's EXTENT, since it traverses by
   index, and for a filtered axis that is the kept COUNT — the same walk
   with `c++` for a payload (`getOrBuildExtent`), computed once at the
   product's exterior and shared, so build and traversal agree on the
   coordinates by construction.

   **The FIBERED read over a chain axis followed** (Main 15r5 filtered,
   15r6 flattened), and it closed by asking what holding an axis actually
   is. The blocker recorded here had been that "an axis is HELD by being
   traversed by index, and the kept firings of a chain are not an indexed
   loop" — true about loops, and the wrong level to state it at. Holding
   an axis is having its COORDINATE, and the coordinate of a chain axis is
   the running count of the firings it produces, because that is the order
   the table build pushed its rows in (`getOrBuildTable` walks the axis's
   own chain) and the number `getOrBuildExtent` counts. So a chain that
   iterates a chain axis mints one counter outside every loop, guard, and
   arm, and hands each firing `const i = c++`, tagged onto the innermost
   segment as its `idxVar` — the same `seg` slot a plain axis's loop index
   fills, so `matchPartialProductChain` and `emitTableTraversal` needed no
   new machinery at all: `axisHeldAt` says which segment carries a held
   axis's coordinate (its own flow for a plain axis, the last span key for
   a chain one) and the rest is the fibered read that already worked.
   Three consequences worth recording. The counter is minted at the
   PAYLOAD point of the walk, so a partial level defers it to its arms —
   a firing landing in an uncovered cell is not a kept firing and
   contributes no row, and the arm that fires is the one that advances the
   count, which is the same sentence `emitRegister` reaches through this
   walk. Nothing distinguishes a filtered chain from a FLATTENED one
   (`join(list, list)`): a dispatch drops firings and a flatten multiplies
   them, and the count does not care, which is why `emitIterCollect` mints
   the identical counter for the pure-iter chain it assembles. And an axis
   held this way still shares the ONE table with a chain that COLLECTS it,
   so both fiberings of a filtered product read the same rows and the
   user's computation runs once per point of the smaller rectangle (both
   tests carry the add-once golden). Still deferred here:
   `Complete` inserting a Cross over a filtered axis (the frontier walk resolves an
   axis key to a list uncollect's flow, and a filtered axis's flow is a
   Join the author may not even have drawn — it stays a witness whose
   remedy is a hand-drawn cross, exactly as a non-list axis does).
   Still deferred (the context-model
   generalization proper): cross of **non-list axes**
   (`product-flows-design.md` open question 6 — `cross(list, option)` is
   not asked for yet, and the stream/async/incremental axes wait on their
   kinds' own rounds); Cross output ports for the barrier
   shape — the poset-VALUED context report, of which the flattened path
   above is the linear projection: the fiber's order-freedom lives in a
   convention two call sites honour, not yet in the type;
   Check admitting products in more shapes; and
   partial collect's **merged-context computation** (the cell-set /
   subset-lattice segment, the *same* non-tree feature — `product-flows-
   design.md`'s "the first non-tree feature: partial-collect's subset
   lattice"). The Delay-over-products case rides on this too.
   **The transposing commute is DONE** (Main 15p) — the row's cheapest
   item, because the work was already paid for. `product-flows-design.md`
   theorem 2 says commute over a crossed pair is TOTAL, and the reason is
   that transpose *re-reads* a product rather than restructuring it. So
   the implementation is a denotation, not an emitter: `Context.through
   Commutes` resolves a commute output port to its operand swapped
   ("outer" = the ex-inner, now outermost), the product matchers key
   their chains through it, and the transposed consumer is just another
   permutation indexing the one shared table — which every k! order
   already did (Main 15p pins add-once on the transposed output). Two
   things worth recording because they are the design speaking rather
   than a choice: (i) the lawfulness GATE costs nothing and lives at the
   call site — the matchers require the resolved flows to be axes of one
   constructed product, so a commute over a genuine nesting resolves to
   flows no Cross crosses and declines exactly as before; that decline is
   now named for what it is, the directed SEQUENCE operation (option out
   of a stream, short-circuiting) waiting on stream flows, the second of
   the two operations `lazy-stream-commute-design.md` says the one word
   covers. (ii) Check's join-adjacency needed a carve-out, and it is
   theorem 1 rather than a loosening: two axes of one product are
   nesting-adjacent BY the product, their own exteriors being sibling. It
   asks CONTAINMENT ("both axes of one product", `Poset.leq`), not the
   exact-span discipline a combine's home gets — the two differ at rank
   ≥ 3, where a flat three-way cross builds no `{X, Z}` sub-product and
   does not need to: inside one cube every pair of axes is order-free, so
   swapping the reading of X and Z is lawful even with Y "between" them
   in the stored orientation. A product has no between. What is still
   owed on the commute is the design's own TODO in the other direction —
   that this Commute should never be *authored* (over a Cross it is
   mandatory and uniquely determined by the consumer's read orientation,
   so the editor should insert it faint, `time-travel-programs-design.md`
   style), which is a Complete-pass item, not an emitter one.
   **Completion inserts a Cross** (Cross's "smallest first step" 3) is
   DONE for the sibling-opens case at **any rank** (`Complete.res`
   `harvest`/`solve`/`realise`; Main tests 10 and 10c): the k≥2 lists
   combine authored with no Cross now has the product spanning exactly
   its axes inserted — a single `Cross(X, Y)` for k=2, a nested
   `Cross(Cross(X, Y), Z)` chain for k≥3 — and compiles via the
   whole-table (cube) emitter, the same values as the hand-drawn form
   (Main 10c ≡ 15d/15e). The full span is read off `Annotate.valueAxes`,
   so a rank-3 combine `f(x,y,z)` reaches all three axes rather than
   completing only the first incomparable pair. `Complete` runs before
   Check (Pipeline), so Check validates the completed program; completion
   is identity for already-committed programs, and non-completable
   clashes (bundle mixing, dependent nesting) are never harvested and
   stay witnesses. The **fully-uncrossed** guard is what keeps an
   under-covered consumer a witness: a combine whose axes are already
   entangled with a partial/overlapping product (Main 15f/15g — {X,Y} and
   {Y,Z} with no full span) has no least upper bound and stays
   time-travel rather than being papered over. (This refines the earlier
   binary rule, which only checked whether the *exact* pair-product
   existed; the axis-entanglement guard is more aligned with the poset's
   "no LUB ⇒ no home" stance and changes only the untested binary edge
   where a combine shares an axis with an unrelated cross.) Still ahead:
   dependent-nesting `Nests` edges from terminations, commute-chain
   lifts, and the canonical heuristic table. (TextPrint's `+` lines are
   DONE — worklist item 4.)
9. **Partial collect** — DONE for the direct slice (`Codegen.res`,
   `emitPartialCollect`, plus a `PartialLevel` in `spine`, the flow-borne
   merged-value context in `Context.res`, and the `~pf` lane binder in
   the text pipeline): a merged flow of k covered cells terminated by a
   join (multi-cell filter) or alone (option), k-arm non-exhaustive
   dispatch, merged value consumed directly. Leading levels may be list,
   option, **or a case-alt dispatch** — the leading-level walk is now the
   unified `filterPlan` (`FIter`/`FAlt`) shared with `emitFilterCollect`,
   so a `join(join(list, option), partial)` nests the dispatch inside the
   list's for-of and the option's defined-check (skipping an absent option
   per firing; Main test 7d), and a `join(join(list, case-alt),
   partial)` is a **filter-then-partial** — keep the alt, then partial-
   collect a subset of a second split over the kept payload, the k-arm
   dispatch nested inside the kept-alt guard (Main test 7h). Main
   tests 7b/7c/7d/7h; beyond the bridge, so validated against hand-computed
   values. **Computation AT the merged context is now DONE too** — the
   doc's `logAndFallback` step (`partial-collect-design.md`, "The merged
   flow as parent scope"), which item 8 had bundled with the poset round.
   It turned out to need no new context *representation*, only the
   **containment theorem** stated as a step-availability relation: a bundle
   step in a path is a cell SET (`Context.cellSet`, computed by walking,
   never stored — a case-alt flow is `{A}`, a merged flow the union of its
   branches'), and `Context.stepAvailableAt` matches a step by identity OR
   by containment, so a value borne at `{A, B}` is available inside each
   constituent cell the dispatch opens. Three call sites read it and
   nothing else changed: `Context.isPrefix` (hence `merge`, so a merged
   value combines with a cell-borne one AT the cell), `Codegen.matchChain`
   (hence `instantiate`, which is what places the computation), and
   `Check`'s flow-borne containment. The emission is the doc's own
   sanctioned choice — once per covered arm, code duplicated, evaluated
   once, since exactly one arm runs (Main 7i/7j, the second with a golden
   on both sides: two arms syntactically, four evaluations over four kept
   firings). The relation is strictly ONE-directional, and that half is a
   witness rather than a crash: `branchInterior` now computes a merged
   flow's interior exactly, so a cell-borne value read at the merged
   context is a `flow-borne` witness (Main 7k) — "it never moves a value
   out of a constituent; getting a value to the merged context is what the
   partial collect's value threading is for".

   **The covering CELL-SET collect landed next**, which is the design's HTTP
   program end to end (Main 7l). Coverage moved from alt PORTS to cell SETS:
   `Program.branchCells` walks a branch flow to the cells of one bundle it
   spans — a direct alt port is `{A}`, a partial collect's merged flow the
   union of its own branches' — and `classifyCollect` is covering-vs-partial
   over those unions, so a collect's branches may be single alts, merged
   flows, or a mix ("two singletons and a pair"). `CaseFull` is thereby
   the covering *configuration* of the partial collect, not a sibling
   construct, which is what the doc always said the node was. Three
   consequences fell out rather than being arranged: the disjointness
   demand becomes a cell-level check (`Check.checkCoverage` — an overlap
   between a merged branch and a singleton one is invisible to a port-name
   comparison, every merged flow's port being `flow`; Main 7m);
   `emitCaseCollect` keeps ONE ARM PER CELL and pre-memoises each partial
   collect's merged value to that cell's own branch value
   (`memoiseMergedValues` — the containment theorem read operationally,
   "each arm binds the same name to its branch's value; exactly one arm
   runs"), so the doc's alternative spelling (one arm guarded by a
   disjunction) buys nothing; and the printer/parser needed no change at
   all — a merged-flow branch is already a `~pf` lane, so the HTTP program
   round-trips. The compatibility carve-out is one line and worth naming: a
   LONE branch on anything but a direct alt port terminates its flow
   (an iter chain, or a merged flow's option-close lift) instead of
   re-merging the same cells.

   **A partial collect built over another partial's merged flow followed**,
   and it needed no new machinery — only the same two moves the covering
   configuration had already made (Main 7n). `spine` resolves a merged
   flow's split by WALKING (`branchCells`) rather than reading its first
   branch's node, and `emitPartialCollect` dispatches over the merged
   flow's CELLS rather than over its branches, each arm calling the shared
   `memoiseMergedValues`. That one call replaced the emitter's hand-rolled
   "compile this branch's value, memoise it as the merged value" pair,
   which was the same thing at depth one. So merging `{ClientError,
   ServerError}` and then merging THAT with `{Redirect}` compiles, with a
   merged-context computation at each depth. Two `Todo`s written for the
   shape became `failwith`s (compiler bugs if reached) instead, since
   `branchCells` now guarantees the split.

   **The last two cell-set gaps closed together**, and both turned out to
   be the same relation applied one step further out.

   *A merged value read from inside one of its cells* (Main 7o) — by a
   chain that opened that cell some OTHER way, an ordinary filter on one
   alt, say — is now resolved ON DEMAND: `emitCollect`'s `CasePartial` arm
   places the value at the cell segment the chain has open and binds the
   covering branch's value there, the same `memoiseMergedValues` the two
   opening emitters call eagerly. It stopped being a `failwith` and became
   the general form of what they do. Reaching it needed one fix in the
   context model first: `collectRemainderFlows` asked whether the collect's
   flow supplies an axis by IDENTITY, so a merged `{A, B}` looked like a
   surviving axis of a collect over the single cell `{A}`; it now asks
   through `stepAvailableAt`, which is the same containment. Reading a
   merged value from a cell the merge does NOT cover stays a `flow-borne`
   witness (Main 7p) — the value does not exist on those firings.

   *Overlapping cell sets* (Main 7q) combine at their MEET —
   bundle-provenance-design.md's "Revision: overlap is incorporate, not a
   clash", `{A,B}` and `{B,C}` meeting at `{B}`. `Context.merge` gained
   `meetPath`/`cellMeetStep` and takes them there, subject to the same
   discipline `Poset.merge` applies to products: the meet must be a set the
   program CONSTRUCTED. A single cell always is — the split's own alt flow
   port, engaged by both merges — which is the doc's own worked example, and
   codegen needed nothing at all, because each merged value then resolves
   inside that cell by the on-demand read above. A meet WIDER than one cell
   with no partial collect spanning it has no constructed home, and
   `classifyClash` now names it (`unconstructed-meet`, Main 7r) instead of
   misfiling it as `time-travel` — whose remedy, "insert a Cross", answers a
   product question, not a bundle one. The same generalisation makes
   DISJOINT merged cell sets bundle mixing (Main 7r): alt ports of one split
   were always caught, but two merged flows live on their own nodes and used
   to look like unrelated opens.

   **The last cell-set gap — a partial level that is not innermost —
   closed by making the level walk RECURSIVE** (Main 7s). A partial level
   BRANCHES: every level after it, and the payload, must be assembled once
   per covered cell under that cell's own context and its own bindings,
   which is exactly what the flat plan-then-assemble walk could not
   express. `buildChain` walks the levels up to the first partial through
   the existing flat `walkFilterLevels`, turns the partial into a k-arm
   dispatch, and recurses on the rest inside each arm; a chain with no
   partial level recurses zero times and is the flat walk it was before.
   So `join(join(list, partial), inner-list)` — keep the error firings,
   then flatten a list derived from each — compiles, the multi-cell twin
   of the filter-then-flatmap shape, with the flattened list itself
   computed at the merged context.

   Doing it collapsed `emitFilterCollect` and `emitPartialCollect` into one
   `emitCellChain`: a case-alt level keeps one cell and a partial level
   keeps k, which is the same construct at two widths, and the doc's three
   terminations (join-absorbed filter, collected alone, covering) then
   differ only in the any-list accumulator and in who owns the arms. The
   merge was not a tidy-up done alongside the feature — it is what the
   feature turned out to be.

   The partial collect's cell-set row is closed, and so is the rest of the
   cell-set world: what was listed on OTHER rows — the **register** over a
   partial merged driving flow and its **running view** — has since landed
   too (items 6(b) and 6(d)), both by assembling through this very
   `buildChain` rather than by growing machinery of their own. Which is the
   same finding a third time: a partial level is a dispatch that keeps k
   cells, and every walk that handles one cell handles k by recursing. Then
   per
   `implementation-strategy.md`: streams, async/incremental — each a new
   species in `Annotate` + cells in `Runtime.res` + an emitter, not a
   restructuring.

## Architecture stubs — where the design has moved ahead of the code

A 2026-07 gap analysis compared the design record against the code and
staged the codeable gaps as **architecture-stub modules**: compiling
ReScript files holding the planned types, the adopted decisions, the
settled rejections (so a fill-in can't re-import a dead end without
tripping over the comment saying why), and `failwith`-bodied function
stubs naming the design doc that specifies each body. Nothing in them
runs or is reachable from the pipeline; each stays staged until its
emitter/check round, so the live matches in `Program.res`/`Codegen.res`
don't grow arms ahead of behaviour. The gate for getting a stub was
"has a worked representation in the record" — adopted **or**
exploration; a mere thought gets a comment, not a module.

| module | design status | what it stages |
|---|---|---|
| `Stream.res` | compile strategy **committed** (Shape C, per-node memoised streams); flows unimplemented | The `Stream` flowKind row; the Delayed-cell runtime spec with its two hard requirements (iterative force, path compression); the two commute *operations* (`SequenceCommute` vs `TransposeCommute` — settled to be distinct); the stack-discipline check; the source-opener riders (`SelfOpen`, `PullSource`). Implementation order 1→2→3→6; the consumer-set lattice is deferred-not-rejected. |
| `Async.res` | exploration; race's pairs-in shape **adopted** (2026-07-23) | The terminator-tag vocabulary; the async cell (`__asyncCell__`/`__startAsync__`, start-is-synchronous); the async uncollect/collect; the race barrier (per-contender (flow, payload) pairs in, per-cell (value, flow) mints out, one node) with the pair-coherence check; the settle node (completions flow, settlement order); `Paced`; cancellation's `ReleaseHalf` (the bracket's late-wired half, DelayWrite-shaped). |
| `Incremental.res` | exploration | The `Var` flowKind row; the pull-baseline cells + generation word; `Hold`/`Changes` kind-crossing nodes; switch-join as a Join variant, not a new species; cutoff left open; the push region deferred behind the same cell interface. |
| `Cut.res` | **adopted** (2026-07-23): end-when + the node-bit, exclusive default; the cut root | `EndWhen` with the three-valued `cutDestination` at the root (end-when's bit is its projection); split-when staged as the *iterated cut* (derived, no node kind); the stop-operand admissibility check; the final-readout anchor left an explicit TODO. |
| `Fail.res` | **adopted** (2026-07-23): fail node, edge stance + super flow, inventory account | `FailOp` (end-when's sibling, no bit); the derived endings inventory (lanes = sets of minting sites, monotone fixpoint, witnesses); the background super flow; the discharge barrier minting outcome cells directly (the `(prefix, term)` pair demoted to a lowering) with its exhaustiveness check. Residue flagged: tag identity across reuse boundaries. |
| `CollectFamily.res` | ladder **adopted** (2026-07-23); keyed collect exploration | The `availability` ladder (monoid → total, semigroup → option-shaped, non-associative → augment-only) classified off the catalog row; the keyed partition with its four readouts. |
| `Property.res` | exploration (its step 1, alignment, is already live in Check) | The 10-row property inventory; demands/offers; the **catalog row** several rounds converge on (identity witness, throw lanes, cancel translation, coalescing); monotone no-choice-points propagation; the boundary projection / principal property signature; the schematic source. |
| `OrderDemand.res` | per-kind half **adopted** (2026-07-23); **no longer a stub** | The owned-order criterion as a five-way `orderClass` (owned / none / incidental / degenerate / surplus) and order provenance (inherited / minted / ambient) as staged types; `orderOf` is now IMPLEMENTED — the kinds table as a structural provenance walk over the flow constructors that exist today (list ⇒ owned, option / case alt ⇒ degenerate, Join ⇒ its operands' orders composed lexicographically, Cross ⇒ surplus, Commute ⇒ the transposed operand's, a partial collect's merged flow ⇒ the parent's restricted). The rule that reads it lives in `Check.res` (`checkOrderDemand`), beside the other witness rules and mirroring how `checkCross` reads `Annotate.crossViolation`. The rows for kinds that do not exist yet (stream, async, incremental, sever→settle bodies, divide-flow siblings, saturation members) stay recorded as comments; the hold identification is still a note. The product (surplus) cell is *located*, not resolved — `product-linearization-design.md` still owns which order a whole-product register would walk, and the commutative-monoid exception waits on `CollectFamily.res`. |
| `Boundary.res` | **jointly adopted** (2026-07-23), anchor-is-identity constraint; served two-ends core adopted | The remembered cut (one directed sorted crossing list, six sorts including the op pair); `Call` vs `Link` on one substrate; the four bindings (function / level / provider / program — `{nodes, outputs}` is the degenerate cut); the measure discipline (3 species × 3 rungs); facet / binding / middleware-splice; derived membership, reusability, signature. Config scopes recorded as dissolved into the op pair. |
| `Effects.res` | exploration with a recorded direction (2026-07-23): IO as a flow | The `IO` flowKind row; ops as uncollects joining into one global IO flow; join's asymmetry as the sequencing; the handle derived; the joins-back check. Within-firing effects deliberately contribute only the coalescing catalog-row bit (on `Property.catalogRow`). |
| `FocusedUpdate.res` | exploration | The getter→setter mirror table as `pathStage`/`setterStage` with the derived `mirror`; the identity-branch-never-filter rule. |
| `Saturation.res` | exploration, blocked on four presumed constructs | The flow back-edge as a `SaturateRead`/`SaturateFeed` pair mirroring the Delay pair; the dedup-collect parameter (set vs keyed-merge); naive/semi-naive as compiler-chosen lowerings. |
| `Edit.res` | exploration (the most stub-ready doc in the record) | `Hole` (representable partiality, planned wires with zero semantics); the cursor position algebra + working record; edits as atomic pure `workingRecord => result<_, refusal>`; the eligibility tiers and `eligible`; the editor-state head-first `historyNode` with the from-scratch-is-the-definition fiat. |

Also staged inside live modules: `Derive.res` grew the catalog-entry
types (pattern / expansion / port correspondence, `DerivedPort`,
reduce-close as the inaugural species); `Complete.res` grew stubs for
its three named remaining bodies (dependent-nesting `Nests` harvesting,
commute-chain lifts, the canonical table as versioned data beside
`heuristicOrderV0`); `Check.res`'s stub section indexes the planned
rules living in the stub modules.

Deliberately **not** stubbed (mere thoughts — no worked representation
to transcribe): trees/zippers (`trees-and-recursion.md` — the 2026-07-23
seam decision is mostly negative: no verifier, no computed-value zipper
ports; the positive remainder has no worked shape), within-firing
effects (adds no construct by design), custom flows (the
user-defined-kind vs catalog-block fork is itself the open question),
configuration scopes (dissolved into the op pair), the
product-linearization residue and the value-in-context model (owe their
evidence), and the running view's surface (semantics fixed, drawing
deliberately left tentative — no port minted for it).

## The JS backend

`src/JsAst.res`, `src/JsPrint.res`, `src/JsBuild.res` are the JS backend:
the typed AST, the precedence-aware printer, and the smart constructors.
Codegen emits `JsAst`, `JsPrint` renders it, and the smoke suite `eval`s
the result. They predate the current compiler and outlived the earlier
one unchanged — the one stable layer under everything above.

There is no longer a legacy/next separation. Until 2026-07 an earlier
lazy compiler (`Expr`/`Compile`/`ExprPrint` and an old `Main`) ran
beside this one as the migration's spec, reached through a disposable
bridge and cross-checked by a differential; once Codegen compiled every
smoke program without falling back, the bridge and those modules were
deleted, `src/next/` moved up to `src/`, and this became the whole
compiler (worklist item 7).
