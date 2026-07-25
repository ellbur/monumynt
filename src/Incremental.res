// The incremental flow (reactive vars) — ARCHITECTURE STUB. Nothing here
// runs; this plans the PULL BASELINE, the first implementation, with the
// push region layered on later behind the same cell interface.
//
// Design: plans/incremental-flow-design.md — EXPLORATION (not adopted).
// Gated on streams (runtime order) and on the async cells (the changes
// adapter is an async-stream bridge).
//
// The two-sided commitment to keep straight:
//   - PURE PULL IS THE BASELINE, and pure bodies make it observably
//     identical to the target — build pull first, add push later, nothing
//     observable moves.
//   - PURE PULL IS REJECTED AS THE LONG-TERM MODEL — the destination is
//     push-with-values inside a NECESSITY FRONTIER (shared with
//     cancellation's strand accounting). Baseline, not target.
//
// Integration points:
//   - Program.res: `flowKind` gains `| Var` (the incremental open: value
//     port = current value, flow port = tracking context; collect -> a
//     var). There is NO "zero-or-one, always" kind and NO "many, always"
//     kind — those table cells are deliberately closed (var<option<X>>
//     instead; no var-of-list row).
//   - Program.res kinds: Hold / Changes below (kind-crossing nodes — just
//     nodes whose port inventories mix flow kinds; the ports model makes
//     the representation the easy part).
//   - Join: the switch-join (join : var<var<X>> -> var<X>) is the SAME
//     binary Join node with a var-kinded operand, not a new species.
//   - Runtime.res: the cells below.
//   - Every cycle must cross a register; the clock is the event-loop turn.

// --- Runtime: cells + the generation word ---------------------------------
//
//   const __gen__ = {n: 0};                        // global generation
//   const __root__ = (v) => ({v, ver: 0});
//   const __setRoot__ = (r, v) => { r.v = v; r.ver++; __gen__.n++; };
//   const __derived__ = (t) => ({v: undefined, ver: 0, at: -1, t});
//   const __readVar__ = (d) => {
//     if (d.at === __gen__.n) return d.v;
//     const r = d.t();
//     if (r.changed) { d.v = r.v; d.ver++; }
//     d.at = __gen__.n; return d.v;
//   };
//
// The generation word carries three properties: a mutation computes NOTHING
// (store, bump version, bump generation — no dependent edges exist at all);
// a read verifies-or-recomputes each node at most once per generation;
// glitch-freedom is automatic (a read is one synchronous pass over a frozen
// generation). Under pull, switch dynamism is nearly free — no subscription
// to tear down, no heights to adjust.
//
// One push survives even in the baseline: push of DEMAND, not values — a
// mutation schedules the once-per-turn microtask that visits pending
// change-stream cells (this sets the batching grain; per-turn vs per-event
// is open q.3).

let incrementalPreludeStmts: unit => array<JsAst.stmt> = () =>
  failwith("stub: __gen__/__root__/__setRoot__/__derived__/__readVar__ prelude — incremental-flow-design.md, 'Compile sketch'")

// --- The planned representation additions ---------------------------------

type plannedFlowKind = VarKind

// The two boundary adapters, async <-> incremental:
type plannedKindCrossing =
  // hold : (X, stream<X>) -> var<X>. Most recent event's payload, or init
  // before any event — the initial value is load-bearing (a var must always
  // be readable). Compiles to a root cell plus a drain of the event stream
  // whose per-event body is __setRoot__. Semantically IDENTIFIED (adopted
  // 2026-07-23, delay-ontology-design.md) with the register on the event
  // stream whose step projects onto the new value — see OrderDemand.res;
  // the compile may still treat the mutation boundary specially.
  | Hold({init: Program.valueRef, events: Program.flowRef})
  // changes : var<X> -> stream<X>. An async-stream adapter holding a
  // pending-cell registry; __setRoot__ schedules the once-per-turn pull.
  // Inherently a LATEST-kind source: a var has no history — intermediate
  // versions were never computed.
  | Changes({var_: Program.flowRef})

// Cutoff: one equality check at each recomputation; ver bumps only on
// change. Observable through `changes`, so it is SEMANTICS, not just
// optimisation. Open q.2: built-in structural equality vs an explicit
// cutoff node carrying a user equivalence vs both — do not harden here.
let emitVarCollect: Program.node => array<JsAst.stmt> = _collect =>
  failwith("stub: incremental collect emitter — incremental-flow-design.md, pull baseline")

// --- Deferred with a warning label (do not build in the baseline) ---------
//
//   - The push region proper: dependent edges, registration events,
//     "a pending pull is a registration", linger-to-turn-end, necessity
//     maintenance under switch-join.
//   - Incremental collections / incr_map diff propagation (open q.6);
//     stream<var> commute; var terminators (open q.4).
//
// Settled rejections a fill-in must not reintroduce: the dirty-bit
// refinement (dirt is value-free — the named dead end for fan-out); a
// filtered close over a var (ill-formed); a var<option<X>> -> option<var<X>>
// commute (absent by criterion, not omission); an imperative
// register/deregister API (dissolved — there is no bare read of a var).
