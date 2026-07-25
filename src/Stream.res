// Stream flows — ARCHITECTURE STUB. Nothing in this module runs yet; it
// plans the shape of the stream implementation so the pieces can be filled
// in later without re-deriving them from the design record.
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
// Integration points (each a local addition, none a restructuring):
//   - Program.res: `flowKind` gains `| Stream`. A stream uncollect is
//     structurally identical to a list uncollect (ports: value "element",
//     flow "flow"); the kind is on the node, chosen explicitly, never
//     inferred.
//   - Annotate.res: `species` gains a stream-cell species; level
//     identification (which source a node's per-element value varies with —
//     the stream analog of the eager `deeper`) is NOT an optimisation and
//     lands with the first emitter.
//   - Runtime.res: grows the Delayed-cell prelude below. This is the point
//     where the prelude stops being three lines and the inline-vs-imported
//     packaging question (compile-strategy open q.3) becomes real.
//   - Codegen.res: a stream collect emitter (each node one memoised
//     stream-derivation cell chained from its inputs; outputs read the
//     chain via Delayed.map / a small zipStream).
//   - The test runner stays synchronous for streams (forcing is pull, not
//     await); async streams are Async.res's turn.
//
// Implementation order (the doc's, with steps 4-5 moved off the critical
// path): 1 runtime primitives -> 2 single-output stream flow -> 3 commute
// on a single-output stream (the motivating operation) -> 6 nested flows.

// --- The planned representation additions ---------------------------------

// Staging type for the Program.flowKind row this round adds. Kept here (not
// in Program.res) so the live pipeline's matches don't grow arms before the
// emitter exists; the fill-in replaces this by a real `| Stream` variant.
type plannedFlowKind = StreamKind

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

// --- Runtime: the Delayed cell (implementation step 1) --------------------
//
// Port of the prototype's cells, SYNCHRONOUS (no promise, no event loop —
// stripping tick() is what creates hazard (a) below). Spec:
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
//   zip          — multi-parent read at the same source position; UNIVERSAL
//                  under the baseline (every node with >=2 inputs).
//
// TWO HARD REQUIREMENTS, both landing here, both correctness-class:
//   (a) ITERATIVE FORCE: force must follow flatMap/redirect chains in a
//       loop, never by recursion — a run of K skipped elements otherwise
//       nests K redirects and a sparse filter over a long source overflows
//       the stack.
//   (b) PATH COMPRESSION: while walking, rewrite each visited cell to the
//       final result, or a retained reference into a skipped run keeps O(K)
//       indirection objects alive.
//
// Invariant carried by every chain: SOURCE-POSITION ALIGNMENT — one cell
// per source element, always. A non-firing element does not delete its
// cell (the cell carries the non-firing as a partial value); subsetting
// happens in exactly one place, the collect's output construction. And a
// non-firing element never emits a placeholder cell — the fold becomes the
// rest.

let streamPreludeStmts: unit => array<JsAst.stmt> = () =>
  failwith("stub: Delayed/stream/zipStream/listToStream prelude — lazy-stream-placement-design.md step 1")

// --- Codegen: the per-node chain (steps 2-3) ------------------------------
//
// Every node in the graph becomes its own memoised stream-derivation cell,
// chained from its inputs (a sub-chain derives from its parent via
// Delayed.flatMap at the same source position). Outputs read the chain via
// a Delayed.map projection or a small zipStream. The honest costs, accepted
// with the baseline: allocation count (one cell per node per source element)
// and RETENTION (memoised history — everything back to the slowest cursor
// stays live; a retained head pins the prefix) — a genuinely new cost axis.

let emitStreamCollect: Program.node => array<JsAst.stmt> = _collect =>
  failwith("stub: stream collect emitter — lazy-stream-placement-design.md step 2 (real signature threads Codegen state + context)")

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
