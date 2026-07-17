// Pass 2 of the compile pipeline: completion — turning an under-committed
// program into a committed one (time-travel-programs-design.md).
//
// STATUS: stub. Today this is the identity on already-committed programs;
// its type is the architecture. The real pass, per the design record:
//
//   1. HARVEST constraints: directed edges from terminations (the authored
//      collect order fully directs a nesting per output) and authored flow
//      operations (join/commute/`in` clauses); undirected comparability
//      edges from combining nodes (an App over two flows demands their
//      contexts become comparable).
//   2. SOLVE: extend the partial order. Ties break by the canonical table,
//      then the heuristic order — both are LANGUAGE SEMANTICS, versioned as
//      such, carried as explicit ordered data (below) from the first real
//      commit so the discipline is structural, not a comment.
//   3. REALISE: insert the operators the solution implies. Sibling opens
//      get a single Cross (orientation from the authored close order) —
//      NOT an Incorporate, which would erase their mutual independence
//      (product-flows-design.md). Incorporate remains the completion for
//      bringing a *value* into a flow context. Lifts insert commute chains.
//
// Commitments the stub already honours by shape:
//   - Completion is translation only: zero runtime representation of
//     unresolved nesting; codegen consumes committed programs (commitment 1
//     of the time-travel doc — testable as compiled-completion ≡
//     hand-completed-program once the pass is real).
//   - Insertions are addressed to authored anchors and returned alongside
//     the program — the lens an editor renders faint and TextPrint renders
//     as `+` lines. They are re-derived, never stored.
//   - Deterministic: same program in, same completion out. Inserted nodes
//     will need composite ids ((anchor id, internal name)), never a counter.

type insertion = {
  anchorNodeId: int, // the authored node the insertion hangs off
  description: string, // human line; becomes TextPrint's `+` rendering
}

type completed = {
  program: Program.program,
  insertions: array<insertion>,
}

// The published tie-breaker order, versioned with the language. Empty at
// v0 — populated when the solver lands (time-travel doc, open questions
// 1-2 demand it be explicit, ordered, versioned data).
let heuristicOrderV0: array<string> = []

let complete = (p: Program.program): completed => {
  // v0: trust the input to be committed. A program that actually needs
  // completion compiles wrong or trips a downstream assert — acceptable
  // only under the honoured-limitations discipline, and only until the
  // harvest/solve/realise pass replaces this body.
  {program: p, insertions: []}
}
