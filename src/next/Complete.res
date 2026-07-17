// Pass 2 of the compile pipeline: completion — turning an under-committed
// program into a committed one (time-travel-programs-design.md).
//
// STATUS: the pass SHAPE is real — harvest -> solve -> realise, each a
// named function with its contract stated — but every body is the v0
// trivial case: a program that harvests no constraints completes to
// itself. A program that actually needs completion currently either trips
// a Check witness (alignment) or compiles wrong — acceptable only under
// the honoured-limitations discipline, and only until these bodies are
// written.
//
// Commitments the skeleton already honours by shape:
//   - Completion is translation only: zero runtime representation of
//     unresolved nesting; codegen consumes committed programs (commitment
//     1 of the time-travel doc — testable as compiled-completion ≡
//     hand-completed-program once the pass is real).
//   - Insertions are addressed to authored anchors and returned alongside
//     the program — the lens an editor renders faint and TextPrint renders
//     as `+` lines. They are re-derived, never stored.
//   - Deterministic: same program in, same completion out. Inserted nodes
//     will need composite ids ((anchor id, internal name)), never a
//     counter — same discipline as Derive's manufactured ids.

open Program

// A constraint harvested from the program, in the time-travel doc's
// vocabulary. Directed nesting edges come from terminations (an authored
// collect order fully directs a nesting per output) and authored flow
// operations (join / commute / explicit `in` clauses); undirected
// comparability demands come from combining nodes (an App over two flows
// demands their contexts become comparable).
type constraint_ =
  | Nests({outer: flowRef, inner: flowRef, why: string})
  | MustCompare({a: flowRef, b: flowRef, why: string})

// One planned/reported insertion, addressed to an authored anchor. When
// realise becomes real this grows a payload (which operator — Cross,
// commute chain, incorporate — and its operand refs); the description
// string is the piece that survives into TextPrint's `+` rendering either
// way.
type insertion = {
  anchorNodeId: int,
  description: string,
}

type completed = {
  program: Program.program,
  insertions: array<insertion>,
}

// The published tie-breaker order, versioned with the language: canonical
// table first, then this heuristic order — both LANGUAGE SEMANTICS, not
// implementation details (time-travel doc, open questions 1-2 demand they
// be explicit, ordered, versioned data). Empty at v0; populated when solve
// lands.
let heuristicOrderV0: array<string> = []

// 1. HARVEST the constraints. v0 harvests nothing, which is honest for
// programs whose wiring is already fully committed. The real harvest walks
// terminations and flow operations for Nests edges and combining nodes for
// MustCompare edges — note that detection here is the front half of what
// checkAlignment/checkProvenance detect; whether they share a traversal is
// compile-strategy-design.md open question 6 (keep the OUTPUTS distinct
// regardless).
let harvest = (_p: program): array<constraint_> => []

// 2. SOLVE: extend the partial order the constraints describe; break ties
// by the canonical table, then heuristicOrderV0. Contradictions (within-
// chain cycles, reversed dependent nestings, bundle mixing) are witnesses,
// not raises — when this lands, its error half feeds back through Check's
// witness surface. Output: the planned insertions the solution implies.
let solve = (_p: program, constraints: array<constraint_>): array<insertion> =>
  if Array.length(constraints) === 0 {
    []
  } else {
    failwith("Complete.solve: not implemented — time-travel-programs-design.md")
  }

// 3. REALISE the plan as inserted operators. Sibling opens get a single
// Cross (orientation from the authored close order) — NOT an Incorporate,
// which would erase their mutual independence (product-flows-design.md);
// Incorporate remains the completion for bringing a *value* into a flow
// context; lifts insert commute chains. Inserted nodes take composite ids.
let realise = (p: program, planned: array<insertion>): completed =>
  if Array.length(planned) === 0 {
    {program: p, insertions: []}
  } else {
    failwith("Complete.realise: not implemented — time-travel-programs-design.md")
  }

let complete = (p: program): completed => realise(p, solve(p, harvest(p)))
