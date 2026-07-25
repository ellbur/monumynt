// Saturation — closure under rules — ARCHITECTURE STUB.
//
// Design: plans/saturation-design.md — EXPLORATION (first worked round,
// leanings only), and BLOCKED: it presumes four pieces of which only the
// register exists today (self-driven opener — Stream.res; keyed collect —
// CollectFamily.res; Cross compiles only at the whole-table top level).
// Stub the shape; do not stub semantics.
//
// The construct: a BACK-EDGE ON A FLOW WIRE, crossing a collect-then-
// uncollect — the register's dual one level up. The duality is the
// representational anchor (mirror the DelayRead/DelayWrite split pair —
// the later feeding act mints its own node, the object graph stays a DAG,
// the cycle is recovered from identity):
//
//   register:   back-edge on a VALUE wire, crosses a Delay,
//               discipline "every value cycle crosses a Delay"
//   saturation: back-edge on a FLOW wire, crosses a DEDUP COLLECT,
//               discipline "every flow cycle crosses a dedup collect"
//
// The dedup collect does double duty: it makes the loop monotone AND makes
// it converge. Naive vs semi-naive evaluation are TWO LOWERINGS OF ONE
// DRAWING — the compiler's choice, never a user knob. The lattice variant
// swaps the set collect for a keyed collect merging by a lawful operator
// (termination broadens from "no new members" to "no member changed
// value"; convergence needs a bounded-height lattice). Provenance (the
// sub-DAG of firings that derived a fact) is a derived view, read off the
// run, never authored — a leaning only.
//
// Termination is deliberately NOT structural: nothing static is checked;
// divergence is drawn as a possibility. Members of a round own NO order
// (OrderDemand.res: NoOrder — a register over the round's members is
// ill-formed; a worklist order is Incidental).

// The read half: the saturated set re-opened as a flow (the strawman's
// `saturate init s0 => s`). init is the seed set.
type plannedSaturateRead =
  | SaturateRead({init: Program.valueRef})

// The write half: the later feeding act (`feed of s`) — one round's derived
// members collected (set-dedup, or keyed-by-operator for the lattice
// variant) and fed back.
type dedupKind =
  | SetDedup
  | KeyedMerge({operatorRow: string}) // a lawful (associative, idempotent-
  // enough) catalog operator; bounded height owed by the row

type plannedSaturateFeed =
  | SaturateFeed({read: Program.node, round: Program.flowRef, dedup: dedupKind})

let emitSaturation: Program.node => array<JsAst.stmt> = _n =>
  failwith("stub: saturation lowering (compiler picks naive vs semi-naive) — saturation-design.md")

// Settled rejections: exposing the worklist (frontier queue and seen-set
// are lowering, never surface); naive/semi-naive as two constructs or a
// knob; materializing the derivation graph as a value; the whole-set
// register as the PRIMARY reading (kept only as the degenerate neighbour);
// a static termination check.
