// The cut — collect-until and split-when — ARCHITECTURE STUB.
//
// Design: plans/end-when-design.md (ADOPTED 2026-07-23, REVISED 2026-08-04
// — the revision notes govern): end-when is FUSED with its downstream
// collect into **collect-until** (working name) — there is NO first-class
// shortened-flow wire, payloads travel value wires, and terminators carry
// only the REASON a flow ended, never data. The staged types below predate
// the fusion and describe the standalone form; a fill-in stages
// CollectUntil (the fused node), not EndWhen.
// plans/variable-rate-consumption-design.md (the cut ROOT decided
// 2026-07-23: end-when and split-when branch off one construct, the cut;
// split-when is the ITERATED cut — a derived/catalog construct, NOT a
// separate primitive, so no SplitWhen node kind may appear here; revised
// 2026-08-04 — the boundary payload re-homed to a value output on the
// outer flow, which is why the iterated cut stays a flow operation while
// end-when fused into its collect).
//
// End-when is a BINARY FLOW OPERATION with asymmetric operands — the same
// operand pattern as join and fail (Fail.res carries the three-verb table).
// Both operands are flows; `stop` must fire in the subject's own context,
// at most once per subject firing (option-kind RELATIVE TO the subject).
// The whole meaning is one law (the law of the shortened flow is untouched
// by the fusion; what moved is the wire/value boundary): the collected
// prefix covers each subject firing, in step, up to but not including the
// first subject firing at which stop fires; there the flow ends with
// terminator = Stopped, REASON ONLY (the stop's payload, if wanted,
// travels a value wire — 2026-08-04, no smuggling). If stop never fires,
// the subject's own end passes through. "First firing at which stop fires"
// is well-defined only on ordered flows (see OrderDemand.res).
//
// Integration points:
//   - Program.res: `kind` gains the EndWhen node below (flow ports: one
//     output, the shortened flow).
//   - Check.res: the restriction rule (stated in the doc, home still owed):
//     a flow option-kind relative to F is an admissible stop operand for
//     any end-when whose subject's firings are a subset of F's firings.
//     Merged stops are valid only where the stop alts are pairwise-disjoint
//     cell sets OF ONE BUNDLE (independent splits admit no merged form).
//   - Fail.res: an end-when is a terminator MINTING SITE (TermStopped) in
//     the derived endings inventory.
//   - Codegen.res: collect-until compiles as a loop break inside the fused
//     node's own loop. (Pre-revision this line read "never as a fused
//     collect mode" — the 2026-08-04 fusion is not that rejected mode: the
//     rejection was a capacity/mode parameter on an ordinary collect;
//     collect-until is one construct whose collect and cut are one node.)

// The destination setting, three-valued AT THE ROOT (on the node, following
// end-when's adopted node-home): where the boundary element goes.
type cutDestination =
  | ToPrefix // inclusive
  | StartsNext // head of the continuation
  | DroppedElement // nowhere

// End-when's adopted bit is the PROJECTION of the three-valued setting when
// the continuation is unused (without a continuation, starts-next and
// dropped are indistinguishable). One bit, ON THE NODE (decided: the stop
// operand is one wire even when it is a k-way merge, so wire-bit and
// node-bit coincide; demoting the bit to data — a (payload, keep-bit)
// product on the stop channel — is rejected). EXCLUSIVE is the default
// reading, not the only form.
// Pre-fusion staging, kept as the record of the operand shape; the fused
// node adds the collect's own operands (branches) to this and drops the
// first-class shortened-flow output.
type plannedCollectUntil =
  | CollectUntil({subject: Program.flowRef, stop: Program.flowRef, inclusive: bool})

// Stacking (worked; theorems of the law, they transfer to fail): in one
// bundle, all stackings are equivalent to the merged form (a level-1
// recognition whose canonical form is the merged one); across independent
// splits, stacking order is content — tie-break theorem: exclusive inner =>
// inner wins; inclusive inner => the tied firing survives into the outer's
// subject => outer wins. Deliberately NOT proposed: a warning when stacked
// stops aren't provably exclusive.
let checkStopOperand: Program.program => array<Check.witness> = _p =>
  failwith("stub: stop-operand admissibility (restriction rule + merged-stop validity gate) — end-when-design.md")

let emitCollectUntil: Program.node => array<JsAst.stmt> = _n =>
  failwith("stub: collect-until emitter — end-when-design.md, revision notes (2026-08-04)")

// --- Deliberately left open (a fill-in must not decide these here) --------
//
//   - The FINAL-READOUT ANCHOR (open q.4): which extent a register write
//     half's `final` reads when subject-flow and shortened-flow consumers
//     coexist — the rule of meaning needs stating, not inheriting from
//     evaluation order. Leave the anchor a TODO, not a default.
//   - Spellings (one word family — `to`/`until` + a third word for
//     dropped — decided once with split-when's setting; the bit must not
//     spell as a flag).
//   - The iterated cut's exact standing (catalog block vs level-1
//     recognition vs both); the continuation on RanOut; payload
//     availability from the continuation side (skip-while taps only the
//     continuation).
//
// Settled rejections: the cut never shortens the subject flow in place
// (retroactivity; breaks one-flow-many-collects); no boolean-per-firing or
// predicate-lambda stop operand; no per-alt keep-bits on a merged stop as
// the primitive; no `advance(k)` count operand ("the count is the
// imperative encoding of a boundary"); no capacity/mode parameter on an
// ordinary collect ("collect until full" — distinct from the 2026-08-04
// fusion, which makes cut-plus-collect one construct, not a mode); no
// mutable running view (truncation belongs downstream of discharge); no
// first-class shortened-flow wire and no data on terminators (2026-08-04).
