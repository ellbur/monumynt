// Stream flows — PARTLY LANDED. Implementation steps 1 and 2 are live and
// live elsewhere (see below); what remains staged here is steps 3 and 6 and
// the exploration riders, so the pieces can be filled in without re-deriving
// them from the design record.
//
// Design: plans/lazy-stream-placement-design.md (the committed baseline),
// plans/lazy-stream-join-design.md (join as a binary flow operation — the
// correction the whole record follows, already honoured by Program.Join),
// plans/lazy-stream-commute-design.md (the commute-variant taxonomy),
// plans/commute-design-notes.md (superseded stopgap, kept for its survey).
//
// STATUS: the compile strategy is COMMITTED (Shape C — the per-node
// memoised stream, the eager runtime-lazy strategy transposed to streams:
// the compiler decides nothing about placement, correctness never depends
// on an analysis). The consumer-set lattice that would merge one conceptual
// loop into one emitted loop is DEFERRED, NOT REJECTED — it is the first
// step of a later optimisation pass, off the critical path.
//
// What a stream flow is: a list flow opens a whole list and iterates it
// eagerly; a stream flow opens a value into a per-element flow PULLED ON
// DEMAND — each element computed only when a downstream consumer asks, and
// then only once. Multi-output is essential: one source can feed several
// consumers that have pulled to different depths.
//
// WHAT LANDED (steps 1-2), and where — each was a local addition, none a
// restructuring, which was the claim:
//   - Program.res: `flowKind` gained `| Stream`, structurally identical to a
//     list uncollect (ports: value "element", flow "flow"); the kind is on
//     the node, chosen explicitly, never inferred. Plus `streamOpenOf`, the
//     one structural question the two passes below ask.
//   - Build.res / the Text* surface: `uncollectStream` and `open stream`,
//     `open list`'s twin down to the handle.
//   - Annotate.res: `species` gained `StreamCell`, read off the flow a
//     collect terminates — so codegen dispatches on the ANNOTATION.
//   - Runtime.res: `streamPreludeStmts` — the Delayed cell (three-state cache
//     plus redirect), iterative force with path compression, `zipStream`,
//     `listToStream`. The prelude stopped being three lines, and the
//     packaging question (compile-strategy open q.3) got its cheapest honest
//     answer: still inline, but LAYERED, so a program pays for the runtime it
//     uses and eager output is unchanged.
//   - Codegen.res: `emitStreamCollect` — `emitIterCollect` with the loop taken
//     out. Placement, the memo, and the element pre-memoisation are all the
//     existing machinery; only the assembled shape differs.
//   - The test runner stays synchronous for streams (forcing is pull, not
//     await); async streams are Async.res's turn.
//
// Level identification — which source a node's per-element value varies with,
// the stream analog of the eager `deeper` — was listed here as the piece that
// "is NOT an optimisation and lands with the first emitter". It did, and it
// needed no new code: `Context.valueContext` already answers it, so a stream
// flow opened inside an eager list flow places its fold inside the enclosing
// loop by the same let-floating every other collect gets (Main 16e).
//
// STILL STAGED: step 3 (the sequence commute — the motivating operation) and
// step 6's remainder (stream-in-stream nesting and the flatten,
// `join(stream, stream)`, which `Codegen.spine` declines with a named gap
// rather than compiling a pull chain as a loop). Shape C PROPER — one memoised
// cell per NODE rather than one fold per collect — is the other piece: the
// baseline compiles multi-output correctly today (Main 16d), but each collect
// folds the source independently, so per-element work still runs once per
// consumer. That sharing is what Shape C buys back for free, and it is a
// placement change inside `emitStreamCollect`, not a semantic one.

// --- The planned representation additions ---------------------------------

// Commute is settled to be a BINARY NODE (the spec's shape: two flow
// inputs, flow outputs {inner, outer}, no value ports — Program.Commute
// already has it). What this round must add is the VARIANT: "commute"
// currently names two different operations, and they must not share a
// constructor (lazy-stream-commute-design.md, "What this doesn't address"):
type commuteVariant =
  // Monadic sequence: consume the nearest stream layer against an
  // option/result-shaped per-element value. Runtime result for the option
  // case: Delayed<option<stream<'x>>> — walk to the end or the first None,
  // short-circuit structural (recursion past the offending cell never
  // invoked). Result-commute (short-circuit on first Err, carrying its
  // payload) is open question 2 — meaning carries; primitive-vs-
  // generalisation undecided.
  | SequenceCommute
  // Grid transpose over a Cross product — a genuinely different operation,
  // the one that actually requires rectangularity (Cross supplies it by
  // construction). Already the poset round's commute (transpose over the
  // point-indexed table); lawful ONLY there.
  | TransposeCommute

// The shape discipline for stacked stages, applied inside-out (nearest the
// opener first). A stack is well-formed iff every stage's requirement is
// met when reached; an ill-formed stack is REJECTED at compile time, never
// given a fallback meaning (Joined(Commuted(..)) is the witness: its
// imagined "flatten the Somes" meaning differs from the real filter on
// [[2,4],[6,7],[8]] — the 6). This is a Check rule when streams land.
let checkStreamStack: Program.program => array<Check.witness> = _p =>
  failwith("stub: stream stack well-formedness — lazy-stream-commute-design.md, 'The shape discipline'")

// --- Runtime: the Delayed cell (step 1) — LANDED in Runtime.res ------------
//
// `Runtime.streamPreludeStmts` is the port of the prototype's cells,
// SYNCHRONOUS (no promise, no event loop — stripping tick() is what CREATES
// hazard (a) below, which is why both hard requirements landed in the
// primitive rather than in any stage). It implements exactly this spec:
//
//   Delayed<'a>  — a memoised computation with a THREE-state cache
//                  (unforced / in-progress / done), plus a REDIRECT state
//                  (this cell's result is another Delayed) so force can
//                  follow become-the-rest chains iteratively.
//   stream<'x>   = SNil | SCons('x, Delayed<stream<'x>>)
//                  Exactly two constructors — SFail/tagged-end is a settled
//                  rejection as a laziness trick for commute (the failable
//                  terminator is a different, Async-round proposal).
//   ready(v)     — a resolved Delayed.
//   Delayed.map / Delayed.flatMap — projection and derivation.
//   zipStream(s, atNil, atCons) — the fold; atNil is the value when the
//                  stream ends; atCons(head, tailFold) may
//                    (a) emit-and-continue: cons, then the tail's fold;
//                    (b) become-the-rest: skip this element, continue AS the
//                        tail's fold (filter's non-firing element; join's
//                        inner-end);
//                    (c) abandon-the-rest: discard the tail, become a
//                        terminal (commute at a None).
//   listToStream(list) — bridge for list-valued sources.
//
// TWO HARD REQUIREMENTS, both correctness-class, both implemented in
// `__forceD__`: (a) ITERATIVE FORCE — redirects are followed in a `while`
// loop, so a run of K skipped elements costs O(1) stack; (b) PATH
// COMPRESSION — every visited cell is rewritten to the final result while
// walking. Both are exercised: 200k consecutive become-the-rest steps run
// without overflowing.
//
// STILL OWED here: `zip` — the multi-parent read at the same source position,
// UNIVERSAL under the baseline (every node with ≥2 inputs). Step 2's fold
// computes the whole per-element subtree inside one atCons, so nothing yet
// reads two chains at one position; `zip` arrives with Shape C's per-node
// cells, which is what creates the second chain to read.
//
// Invariant carried by every chain: SOURCE-POSITION ALIGNMENT — one cell
// per source element, always. A non-firing element does not delete its
// cell (the cell carries the non-firing as a partial value); subsetting
// happens in exactly one place, the collect's output construction. And a
// non-firing element never emits a placeholder cell — the fold becomes the
// rest.

// --- Codegen: the per-node chain (Shape C proper) -------------------------
//
// Step 2 (LANDED as `Codegen.emitStreamCollect`) is one fold per collect: the
// branch's whole value subtree runs inside the atCons. That is correct and
// placement-free, and multi-output works on it by construction — but per-node
// SHARING is what Shape C adds: every node in the graph becomes its own
// memoised stream-derivation cell, chained from its inputs (a sub-chain
// derives from its parent via Delayed.flatMap at the same source position),
// so sibling collects pull the same cells instead of each re-deriving.
// Outputs then read the chain via a Delayed.map projection or a small
// zipStream. The honest costs, accepted with the baseline: allocation count
// (one cell per node per source element) and RETENTION (memoised history —
// everything back to the slowest cursor stays live; a retained head pins the
// prefix) — a genuinely new cost axis.

let emitStreamCommute: Program.node => array<JsAst.stmt> = _commute =>
  failwith("stub: sequence-commute output construction — lazy-stream-commute-design.md; step 3, the motivating operation")

// --- Source openers (exploration rider) -----------------------------------
//
// plans/source-openers-design.md (EXPLORATION — leanings only, but the bare
// opener has the most concrete port inventory in the record). It rides here
// because the minted flow IS a stream — the sourceless instantiation of the
// existing kind; paced/awaited firings make it an async stream. NOT a new
// flow-kind row.
//
//   SelfOpen — the self-driven opener: NO value inputs, NO value outputs,
//     ONE flow output (the mint). Extent unbounded; shortening is all
//     consumer-side (end-when, interrupt, bounded-prefix demand). Two
//     SelfOpen nodes are two independent flows (identity = node identity).
//     Settled: no firing-index value port (an ambient index is a magic
//     value nobody wired).
//   PullSource — external pull source: a CATALOG BLOCK whose output is a
//     failable stream; mapping FIXED, not configurable (value -> firing,
//     exhaustion -> RanOut terminator, raise -> Fail payload). The interior
//     is deliberately not designed — fence it as an opaque block, never a
//     lowering.
//   Pacing (`paced(F, g)`) lives with the binary flow-operation family in
//     Async.res (the gate is an async value's settlement).
type plannedSourceOpener =
  | SelfOpen
  | PullSource({externSource: string})
