// Pass 2 of the compile pipeline: completion — turning an under-committed
// program into a committed one (time-travel-programs-design.md).
//
// STATUS: harvest -> solve -> realise are real for the sibling-opens
// completion at ANY rank — the k>=2 lists program without a hand-drawn
// Cross has the product spanning exactly its axes inserted for it (the
// binary two-lists case and the rank-3+ cube, `cross(cross(x,y),z)`,
// authored automatically). Programs past that (dependent-nesting Nests
// edges, commute-chain lifts, the canonical heuristic table) still either
// trip a Check witness or compile wrong — acceptable only under the
// honoured-limitations discipline, and only until those bodies are written.
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
// demands their contexts become comparable). `anchor` is the authored node
// the demand arose at — an inserted operator is addressed to it (the faint-
// rendering lens).
type constraint_ =
  | Nests({outer: flowRef, inner: flowRef, why: string})
  // A sibling combine over k>=2 mutually-invariant top-level list axes with no
  // constructed product touching any of them: it demands a product spanning
  // EXACTLY those axes. `flows` are the axis flows in a canonical (flow-key)
  // order — the product's stored orientation, which is free (every collect order
  // indexes one shared table), so any deterministic order serves.
  | MustCross({flows: array<flowRef>, anchor: int, why: string})

// A planned insertion carrying its operator payload — the piece `solve` hands
// `realise` (the public `insertion` keeps only the anchor + description, since
// that is all the faint-rendering lens and TextPrint's `+` line consume). One
// planned product spans `flows` (k>=2 axes); `realise` mints it as a left-nested
// chain of k-1 binary Crosses.
type plannedCross = {anchorNodeId: int, flows: array<flowRef>}

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

// Are every pair of these flows MUTUALLY INVARIANT (Cross's demand)? A
// dependence between any pair would be a witnessed dependent nesting, not a
// completable product, so it must not be papered over.
let allInvariant = (flows: array<flowRef>): bool => {
  let ok = ref(true)
  let n = Array.length(flows)
  for i in 0 to n - 1 {
    for j in i + 1 to n - 1 {
      switch Annotate.crossViolation(flows->Array.getUnsafe(i), flows->Array.getUnsafe(j)) {
      | Some(_) => ok := false
      | None => ()
      }
    }
  }
  ok.contents
}

// 1. HARVEST the constraints. Implemented for the sibling-opens combine at ANY
// rank — the k>=2 lists program without a hand-drawn Cross (product-flows-
// design.md, "smallest first step" 3 and its N-ary section; time-travel-
// programs-design.md's disposition 4). A combining node whose value spans k
// INCOMPARABLE sibling flows demands a comparability that only a product
// supplies: an App over k independent top-level list opens, pairwise mutually
// invariant, with no constructed Cross touching any of them. That is a
// completable time-travel gap — harvest a MustCross so solve/realise insert the
// exact product (a nested Cross chain for k>=3).
//
// The full span is read off `Annotate.valueAxes` (order- and comparability-free,
// so it reaches EVERY axis of the combine, not just the first incomparable pair
// the linear `valueContext` raise names). "Fully uncrossed" — no axis of the
// combine appears in any constructed product — is what keeps the UNDER-COVERED
// consumer a witness: a combine whose axes are entangled with an existing
// (possibly partial) product, e.g. two overlapping sub-products {X,Y} and {Y,Z}
// with no full span, has no least upper bound and stays time travel rather than
// being papered over (product-flows-design.md, N-ary; Main 15f/15g).
//
// Deliberately NOT harvested (each stays a witness, unchanged):
//   - bundle mixing (sibling alt flows of one split) — no product exists, the
//     missing fact is an execution (its offending flows are not list axes);
//   - dependent nesting — comparable contexts (prefix), so no clash is raised,
//     and any dependent pair fails `allInvariant`;
//   - siblings sharing an outer loop / non-list axes — not top-level list opens,
//     so a span axis fails the axis-flow lookup (they need a hand-drawn Cross);
//   - an under-covered consumer — some span axis is already in a product.
//
// Detection here is the front half of what checkAlignment detects; the two keep
// distinct OUTPUTS (compile-strategy-design.md open question 6).
let harvest = (p: program): array<constraint_> => {
  let out: array<constraint_> = []
  // Axis keys already covered by SOME constructed product — the "fully
  // uncrossed" guard.
  let crossedAxes =
    Context.productsIndex(p)->Array.reduce([], (acc, pt) => Array.concat(acc, Poset.axes(pt)))
  // Top-level list axis flows, keyed so a value's axis span resolves to flows.
  let axisFlows: Map.t<string, flowRef> = Map.make()
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | Uncollect({flowKind: List, nesting: None}) => {
        let f = FlowPort(n, "flow")
        Map.set(axisFlows, Context.flowKey(f), f)
      }
    | _ => ()
    }
  )
  p.nodes->Array.forEach(n =>
    valuePorts(n.kind)->Array.forEach(port =>
      switch Context.valueContext(ValuePort(n, port)) {
      | _ => ()
      | exception Context.Incomparable(_) =>
        // A sibling combine: its value has no linear context. Gather its full
        // axis span; complete it only when every axis is a top-level list open,
        // the axes are pairwise invariant, and none is already crossed.
        let vaxes = Poset.dedup(Annotate.valueAxes(ValuePort(n, port)))
        let flows = vaxes->Array.filterMap(k => Map.get(axisFlows, k))
        if (
          Array.length(flows) === Array.length(vaxes) &&
          Array.length(flows) >= 2 &&
          allInvariant(flows) &&
          vaxes->Array.every(k => !(crossedAxes->Array.includes(k)))
        ) {
          // Canonical orientation: axes sorted by flow key. The stored
          // orientation is free (every collect order indexes one shared table),
          // so a deterministic order is all that is needed.
          let ordered =
            flows->Array.toSorted((a, b) => Context.flowKey(a) < Context.flowKey(b) ? -1. : 1.)
          Array.push(
            out,
            MustCross({
              flows: ordered,
              anchor: n.id,
              why: "sibling combine at node " ++
              Int.toString(n.id) ++
              " over " ++
              Int.toString(Array.length(ordered)) ++
              " axes",
            }),
          )
        }
      }
    )
  )
  out
}

// 2. SOLVE: turn the harvested demands into planned insertions. Each MustCross
// implies one product; several combines over the same axis SET collapse to one
// product (deduped by the canonical flow-key sequence — the flows arrive sorted,
// so the join is a set key; first seen wins — deterministic by node-scan order,
// the v0 tie-break standing in for the canonical table + heuristicOrderV0).
// Contradictions (within-chain cycles, reversed dependent nestings, bundle
// mixing) are never harvested, so they stay Check's witnesses.
let solve = (_p: program, constraints: array<constraint_>): array<plannedCross> => {
  let seen: Map.t<string, bool> = Map.make()
  let out: array<plannedCross> = []
  constraints->Array.forEach(c =>
    switch c {
    | MustCross({flows, anchor}) =>
      let key = flows->Array.map(Context.flowKey)->Array.join("|")
      if !Map.has(seen, key) {
        Map.set(seen, key, true)
        Array.push(out, {anchorNodeId: anchor, flows})
      }
    | Nests(_) => ()
    }
  )
  out
}

// 3. REALISE the plan as inserted operators. Sibling opens get a product — NOT
// an Incorporate, which would erase their mutual independence (product-flows-
// design.md); Incorporate remains the completion for bringing a *value* into a
// flow context; lifts insert commute chains. A k-axis product is minted as a
// left-nested chain of k-1 binary Crosses (`Cross(Cross(f0,f1),f2)…`), exactly
// the shape a hand-authored `cross(cross(x,y),z)` builds — the whole-table
// emitter flattens it back to the flat axis set (Codegen.productAxesOf). The
// inserted Crosses are new root-unreachable nodes in the set (like a write
// half): productOf and productsIndex scan the whole node set, so both the
// checker and the whole-table emitter pick them up. Ids are minted
// deterministically above the program's ids (a counter suffices while ids are
// program-local; composite ((anchor, name)) ids arrive when derive/complete
// interleave). One insertion is REPORTED per product (the faint-rendering lens
// sees one crossing, however many binary nodes back it).
let realise = (p: program, planned: array<plannedCross>): completed =>
  if Array.length(planned) === 0 {
    {program: p, insertions: []}
  } else {
    let nextId = ref(p.nodes->Array.reduce(0, (m, n) => n.id > m ? n.id : m))
    let newNodes: array<node> = []
    let insertions: array<insertion> = []
    planned->Array.forEach(pc => {
      // Fold the sorted axis flows into a left-nested Cross chain.
      let acc = ref(pc.flows->Array.getUnsafe(0))
      for i in 1 to Array.length(pc.flows) - 1 {
        nextId := nextId.contents + 1
        let cross = {id: nextId.contents, kind: Cross({left: acc.contents, right: pc.flows->Array.getUnsafe(i)})}
        Array.push(newNodes, cross)
        acc := FlowPort(cross, "flow")
      }
      Array.push(
        insertions,
        {
          anchorNodeId: pc.anchorNodeId,
          description: "Cross(" ++
          pc.flows->Array.map(Context.flowKey)->Array.join(", ") ++
          ") — sibling opens crossed to give the combine a product home",
        },
      )
    })
    {program: {nodes: Array.concat(p.nodes, newNodes), outputs: p.outputs}, insertions}
  }

let complete = (p: program): completed => realise(p, solve(p, harvest(p)))

// --- Remaining bodies (ARCHITECTURE STUBS; time-travel-programs-design.md) --
//
// The three pieces the STATUS header names, staged so the shapes are on
// record. Commitments they must keep: completion inserts ONLY operations
// whose value-level shadow is the identity (never value nodes, joins,
// filters, or collects — those change firing structure, which is meaning
// the user must draw); sibling opens are completed by CROSS, never by
// Incorporate (settled — re-rooting erases mutual invariance); bundle
// mixing stays an error, always; opens are never silently duplicated for
// per-consumer completion; and the four laws — conservativity, idempotence,
// determinism, solidification stability — hold as test obligations.

// Dependent-nesting Nests edges: terminations (an authored collect order
// fully directs a nesting per output) and authored flow ops (join/commute/
// explicit `in`) harvest DIRECTED edges; solve is partial-order extension
// over a finite set, every tie broken by published rule, no scoring, no
// backtracking. Four dispositions: determined / canonically completed /
// heuristically completed / contradictory.
let harvestNests: program => array<constraint_> = _p =>
  failwith("stub: dependent-nesting Nests harvesting — time-travel-programs-design.md, rules 2-3")

// Commute-chain lifts: the second insertion family — chains of commutes
// lifting a flow toward its canonical position (rule 5's canonical
// commutes per flow-kind pair). Gated on the commute emitter (the poset
// round) and on streams for the inaugural table entry.
let planCommuteChain: program => array<insertion> = _p =>
  failwith("stub: commute-chain lifts — time-travel-programs-design.md, rule 5")

// The canonical commute table, versioned with the language exactly like
// heuristicOrderV0 (both lists are ONE semantic surface; growing the table
// re-classifies previously-heuristic picks, which is a language change).
// Inaugural entry when streams land: option/error flows commute OUTWARD.
let canonicalTableV0: array<string> = []
