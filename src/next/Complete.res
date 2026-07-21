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
// demands their contexts become comparable). `anchor` is the authored node
// the demand arose at — an inserted operator is addressed to it (the faint-
// rendering lens).
type constraint_ =
  | Nests({outer: flowRef, inner: flowRef, why: string})
  | MustCompare({a: flowRef, b: flowRef, anchor: int, why: string})

// A planned insertion carrying its operator payload — the piece `solve` hands
// `realise` (the public `insertion` keeps only the anchor + description, since
// that is all the faint-rendering lens and TextPrint's `+` line consume).
type plannedCross = {anchorNodeId: int, left: flowRef, right: flowRef}

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

// A supported product axis for the whole-table Cross emitter: a single
// top-level list uncollect flow. Completion only inserts a Cross the emitter
// can compile (Codegen.productAxisOf's shape) — a siblings-sharing-an-outer-
// loop or non-list axis would need the deferred poset round, so it is left to
// witness rather than completed to an uncompilable node.
let isTopLevelListAxis = (f: flowRef): bool =>
  switch f {
  | FlowPort(n, "flow") =>
    switch n.kind {
    | Uncollect({flowKind: List, nesting: None}) => true
    | _ => false
    }
  | _ => false
  }

// 1. HARVEST the constraints. Implemented for the sibling-opens combine —
// the two-lists program without a hand-drawn Cross (product-flows-design.md,
// "smallest first step" 3; time-travel-programs-design.md's disposition 4).
// A combining node whose value spans two INCOMPARABLE sibling flows demands a
// comparability that only a product supplies: an App over two independent
// top-level list opens, mutually invariant, with no constructed Cross yet
// covering them. That is a completable time-travel gap — harvest a MustCompare
// so solve/realise insert the exact Cross.
//
// Deliberately NOT harvested (each stays a witness, unchanged):
//   - bundle mixing (sibling alt flows of one split) — no product exists, the
//     missing fact is an execution (its offending flows fail isTopLevelListAxis);
//   - dependent nesting — comparable contexts (prefix), so no clash is raised;
//   - n-ary combines (three-plus sibling axes) — the value spans more than the
//     two flows the raise names, caught by the exact-span guard; the binary
//     whole-table emitter cannot compile them (the poset round).
//
// Detection here is the front half of what checkAlignment detects; the two keep
// distinct OUTPUTS (compile-strategy-design.md open question 6).
let harvest = (p: program): array<constraint_> => {
  let out: array<constraint_> = []
  let products = Context.productsIndex(p)
  p.nodes->Array.forEach(n =>
    valuePorts(n.kind)->Array.forEach(port =>
      switch Context.valueContext(ValuePort(n, port)) {
      | _ => ()
      | exception Context.Incomparable({left, right}) =>
        switch (left, right) {
        | ([fa], [fb])
          if isTopLevelListAxis(fa) &&
          isTopLevelListAxis(fb) &&
          Context.flowKey(fa) !== Context.flowKey(fb) =>
          // Mutually invariant siblings (Cross's demand)? A dependence would be
          // a witnessed dependent nesting, not a completable product.
          switch Annotate.crossViolation(fa, fb) {
          | Some(_) => ()
          | None =>
            // The value spans EXACTLY these two axes (excludes n-ary combines,
            // whose pairwise raise names only two of three-plus axes).
            let vaxes = Poset.dedup(Annotate.valueAxes(ValuePort(n, port)))
            let need = [Context.flowKey(fa), Context.flowKey(fb)]
            let spansExactly =
              Array.length(vaxes) === 2 && need->Array.every(k => vaxes->Array.includes(k))
            // A constructed Cross already covering the combine? Then it is not
            // under-determined — nothing to insert.
            let alreadyCovered = switch Poset.merge(
              ~products,
              Context.pathToPoset([fa]),
              Context.pathToPoset([fb]),
            ) {
            | _ => true
            | exception Poset.Incomparable(_, _) => false
            }
            if spansExactly && !alreadyCovered {
              Array.push(
                out,
                MustCompare({
                  a: fa,
                  b: fb,
                  anchor: n.id,
                  why: "sibling combine at node " ++ Int.toString(n.id),
                }),
              )
            }
          }
        | _ => ()
        }
      }
    )
  )
  out
}

// 2. SOLVE: turn the harvested demands into planned insertions. For the
// sibling-opens case each MustCompare implies one Cross; several combines over
// the same axis pair collapse to one Cross (deduped by the unordered pair of
// flow keys, first orientation seen wins — deterministic by node-scan order,
// the v0 tie-break standing in for the canonical table + heuristicOrderV0).
// Contradictions (within-chain cycles, reversed dependent nestings, bundle
// mixing) are never harvested, so they stay Check's witnesses.
let solve = (_p: program, constraints: array<constraint_>): array<plannedCross> => {
  let seen: Map.t<string, bool> = Map.make()
  let out: array<plannedCross> = []
  constraints->Array.forEach(c =>
    switch c {
    | MustCompare({a, b, anchor}) =>
      let ka = Context.flowKey(a)
      let kb = Context.flowKey(b)
      let key = ka < kb ? ka ++ "|" ++ kb : kb ++ "|" ++ ka
      if !Map.has(seen, key) {
        Map.set(seen, key, true)
        Array.push(out, {anchorNodeId: anchor, left: a, right: b})
      }
    | Nests(_) => ()
    }
  )
  out
}

// 3. REALISE the plan as inserted operators. Sibling opens get a single
// Cross (orientation from the combine's operand order) — NOT an Incorporate,
// which would erase their mutual independence (product-flows-design.md);
// Incorporate remains the completion for bringing a *value* into a flow
// context; lifts insert commute chains. The inserted Cross is a new
// root-unreachable node in the set (like a write half): productOf and
// productsIndex scan the whole node set, so both the checker and the
// whole-table emitter pick it up. Its id is minted deterministically above the
// program's ids (a counter suffices while ids are program-local; composite
// ((anchor, name)) ids arrive when derive/complete interleave).
let realise = (p: program, planned: array<plannedCross>): completed =>
  if Array.length(planned) === 0 {
    {program: p, insertions: []}
  } else {
    let maxId = p.nodes->Array.reduce(0, (m, n) => n.id > m ? n.id : m)
    let newNodes: array<node> = []
    let insertions: array<insertion> = []
    planned->Array.forEachWithIndex((pc, i) => {
      let cross = {id: maxId + 1 + i, kind: Cross({left: pc.left, right: pc.right})}
      Array.push(newNodes, cross)
      Array.push(
        insertions,
        {
          anchorNodeId: pc.anchorNodeId,
          description: "Cross(" ++
          Context.flowKey(pc.left) ++
          ", " ++
          Context.flowKey(pc.right) ++
          ") — sibling opens crossed to give the combine a product home",
        },
      )
    })
    {program: {nodes: Array.concat(p.nodes, newNodes), outputs: p.outputs}, insertions}
  }

let complete = (p: program): completed => realise(p, solve(p, harvest(p)))
