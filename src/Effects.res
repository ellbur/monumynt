// Per-firing effects — IO as a flow — ARCHITECTURE STUB.
//
// Design: plans/effects-design.md — EXPLORATION, with a RECORDED DIRECTION
// (2026-07-23) that supersedes the handle framing and is what this stub
// plans: IO IS A FLOW, NOT A HANDLE. plans/within-firing-effects-design.md
// deliberately adds NO construct (within a firing there is no time; the
// only intra-firing order is along a handle's segment) — its one stubbable
// artifact, the coalescing catalog row, lives on Property.catalogRow.
// plans/custom-flows.md is the raw material behind both; still
// narrative-stage (the user-defined-flow-kind vs catalog-block fork is
// itself open) — nothing to stub there.
//
// The direction, in this repo's vocabulary:
//   - An IO op does not take a handle in; it UNCOLLECTS — minting an inner
//     IO flow that must JOIN into a containing IO flow, up to one GLOBAL IO
//     flow (flow is forced global).
//   - SEQUENCING IS JOIN'S EXISTING ASYMMETRY: join(outer, inner) means
//     outer's ops happen before inner's — monadic join drawn in the
//     record's vocabulary. Program.Join already has the shape.
//   - The HANDLE IS DERIVED, not primitive — the handle wire IS the flow
//     wire; no new wire species, no bespoke linearity rule (linearity
//     cannot break because everything must join back). Handle notation and
//     inner-flow notation are textual synonyms.
//   - Structural requirements on the drawing: inner flows join DIRECTLY to
//     the global wire, never to each other first (associativity gives the
//     normal form; a renderer may rebracket as a derived view); the join
//     node's output is IDENTIFIED with its outer input.
//   - Commuting an IO flow out of a list flow SEQUENCES the operations:
//     per-firing segments concatenate in firing order into one segment
//     (zero segments concatenate to nothing). For a spanning handle the
//     commute is MANDATORY AND UNIQUE (the flow is linear), so it is NEVER
//     AUTHORED BUT NEVER ABSENT — inferred by published rule and shown
//     faint (the commute-completion ruling; showing it is required).
//   - Two structurally-distinguished shapes, read off the drawing (never a
//     mode): the flow SPANS the loop (threaded, ordered) vs NESTS inside
//     the firing (independent, unordered, per-firing-minted, never crosses
//     the loop boundary).
//
// Integration points:
//   - Program.res: `flowKind` gains an IO row; op nodes are Uncollects of
//     that kind (one op = one uncollect minting its inner IO flow).
//   - Complete.res: the mandatory IO commute is a completion (published
//     rule, faint rendering, `+` lines).
//   - OrderDemand.res: "the IO handle is a wire, not a flow" in the delay
//     doc's table is FILED FOR RE-READ against this direction.

type plannedFlowKind = IOKind

// An IO operation: uncollects the global (or a containing) IO flow into an
// inner flow carrying this op's ordering, with the op's own value inputs /
// outputs as ordinary wires. Exact shape owed to the round; the fork/join
// readability program (granularity dissolves into readability) is OWED
// WORK, not designed.
type plannedIOOp =
  | IOOp({rowName: string, args: array<Program.valueRef>})

let checkIOJoinsBack: Program.program => array<Check.witness> = _p =>
  failwith("stub: every minted IO flow joins back to the global flow, directly — effects-design.md, 'IO as a flow'")

// Settled rejections: prefix-reading the handle into each firing (it is
// linear, not a constant); collecting an effect flow as a list of handles;
// modelling the loop/IO meeting as a Cross (no independence there); an
// author-selected ordered/unordered mode (order is a structural fact); the
// register-on-a-marker-wire reading (dissolved — no Delay appears anywhere
// in the effects story); effects-as-collected-plan as the default; an
// intra-firing sequencing construct (statement order, seq edges); a buffer
// as a mid-firing register read "at the flush point"; a reset op/port on a
// register; cross-handle ordering annotations (fix granularity instead).
