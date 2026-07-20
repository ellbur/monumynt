// Pass 1 of the compile pipeline: whole-program well-formedness checks
// with witnesses (compile-strategy-design.md; check logic per
// types-design.md and bundle-provenance-design.md).
//
// The error surface, decided here (implementation-strategy.md flags it as
// worth deliberateness): a check produces WITNESSES — records addressed to
// authored node ids, carrying a stable rule name and a human sentence.
// Checks never raise for user-level problems; raising is reserved for
// compiler bugs. Everything downstream (test runner now, editor later)
// renders witnesses; passes that *require* a clean program take the
// checked program, not the raw one.
//
// Implemented today:
//   - port-exists     every wire names a port in the target kind's
//                     inventory (the one uniform question the ports
//                     migration promised).
//   - write-count     exactly one DelayWrite per DelayRead.
//   - alignment(v0)   combining values from incomparable contexts, via
//                     Context's prefix-rule merge. Blunt: it cannot yet
//                     tell time travel (completable) from bundle mixing
//                     (not) — that classification needs provenance origins.
//   - join-adjacency  Join/Commute operands must be nesting-adjacent
//                     (lazy-stream-join-design.md).
//   - flow-borne(v0)  a per-iteration value escaping to a program output
//                     (types-design.md); the general interior rule is the
//                     fill-in noted at the check.
//   - coverage        collect branches form a coherent bundle: mixed splits
//                     and non-alt multi-branch collects (via classifyCollect)
//                     plus duplicate-alt coverage — pairwise disjoint
//                     (partial-collect-design.md).
//
// Stubbed with signatures (each names its design doc):
//   - productivity    every cycle crosses a register pairing
//                     (first-class-ports-design.md, the pair section).
//                     Unreachable today: the object graph is a DAG by
//                     construction and the only cycle is the register
//                     pairing itself, so every buildable program is
//                     productive; it becomes load-bearing once a
//                     representation admits foreign cycles.
//   - provenance      cell-level disjointness / mixing-vs-time-travel
//                     classification (bundle-provenance-design.md).

open Program

type witness = {
  nodeId: int, // addressed to the authored node
  rule: string,
  message: string,
}

// --- port-exists -----------------------------------------------------------

let checkPortExists = (p: program): array<witness> => {
  let out: array<witness> = []
  p.nodes->Array.forEach(n => {
    let ins = inputs(n)
    ins.values->Array.forEach(r =>
      switch r {
      | ValuePort(target, port) =>
        if !(valuePorts(target.kind)->Array.includes(port)) {
          Array.push(
            out,
            {
              nodeId: n.id,
              rule: "port-exists",
              message: kindName(target.kind) ++
              " node " ++
              Int.toString(target.id) ++
              " has no value port \"" ++
              port ++ "\"",
            },
          )
        }
      }
    )
    ins.flows->Array.forEach(r =>
      switch r {
      | FlowPort(target, port) =>
        if !(flowPorts(target.kind)->Array.includes(port)) {
          Array.push(
            out,
            {
              nodeId: n.id,
              rule: "port-exists",
              message: kindName(target.kind) ++
              " node " ++
              Int.toString(target.id) ++
              " has no flow port \"" ++
              port ++ "\"",
            },
          )
        }
      }
    )
  })
  out
}

// --- write-count -------------------------------------------------------------
// On the pair spelling this is a whole-graph counting check ("quotient
// constraint enforced as a check, not by construction"). Under a future
// thread-port spelling it would become wire linearity.

let checkWriteCount = (p: program): array<witness> => {
  let out: array<witness> = []
  let writes: Map.t<int, int> = Map.make()
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | DelayWrite({read}) =>
      let c = Map.get(writes, read.id)->Option.getOr(0)
      Map.set(writes, read.id, c + 1)
    | _ => ()
    }
  )
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | DelayRead(_) =>
      switch Map.get(writes, n.id)->Option.getOr(0) {
      | 0 =>
        Array.push(
          out,
          {
            nodeId: n.id,
            rule: "write-count",
            message: "register read has no write half — the register never advances",
          },
        )
      | 1 => ()
      | k =>
        Array.push(
          out,
          {
            nodeId: n.id,
            rule: "write-count",
            message: "register read has " ++ Int.toString(k) ++ " write halves; exactly one is allowed",
          },
        )
      }
    | _ => ()
    }
  )
  out
}

// --- alignment (v0) ----------------------------------------------------------

let checkAlignment = (p: program): array<witness> => {
  let out: array<witness> = []
  p.nodes->Array.forEach(n => {
    // Probe the node's own output ports: computing a port's context is
    // what merges the input contexts (an App's args, a Cross's operands),
    // so this is where incomparability surfaces.
    try {
      valuePorts(n.kind)->Array.forEach(port => {
        let _ = Context.valueContext(ValuePort(n, port))
      })
      flowPorts(n.kind)->Array.forEach(port => {
        let _ = Context.flowContext(FlowPort(n, port))
      })
    } catch {
    | Context.Incomparable({left, right, where}) =>
      Array.push(
        out,
        {
          nodeId: n.id,
          rule: "alignment",
          message: "incomparable flow contexts " ++
          left ++
          " vs " ++
          right ++
          " at " ++
          where ++ " (time travel or bundle mixing; classification TODO)",
        },
      )
    }
  })
  out
}

// --- stubs -------------------------------------------------------------------

// Join/Commute operands must be nesting-adjacent: the inner flow's exterior
// must end exactly at the outer flow (lazy-stream-join-design.md). This is
// the structural fact Codegen's spine walk asserts; checking it here keeps
// that an assert, not a user-facing crash.
let checkJoinAdjacency = (p: program): array<witness> => {
  let out: array<witness> = []
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | Join({outer, inner}) | Commute({outer, inner}) =>
      try {
        let innerExterior = Context.flowContext(inner)
        let expected = Array.concat(Context.flowContext(outer), [outer])
        if Context.contextToString(innerExterior) !== Context.contextToString(expected) {
          Array.push(
            out,
            {
              nodeId: n.id,
              rule: "join-adjacency",
              message: "operands are not nesting-adjacent: inner opens in " ++
              Context.contextToString(innerExterior) ++
              " but the outer flow's interior is " ++
              Context.contextToString(expected),
            },
          )
        }
      } catch {
      | Context.Incomparable(_) => () // alignment reports that clash
      }
    | _ => ()
    }
  )
  out
}

let checkProductivity = (_p: program): array<witness> => {
  // TODO(first-class-ports-design.md): every cycle in the value graph +
  // write→read pairing edges crosses a pairing edge. Requires the write
  // index (Annotate) — the pipeline lets check consume annotate's facts or
  // recompute them; keep the outputs distinct either way.
  []
}

let checkProvenance = (_p: program): array<witness> => {
  // TODO(bundle-provenance-design.md): origins on context paths; classify
  // clashes as mixing (hard error) vs time travel (completable — handed to
  // Complete as its constraint harvest; detection is the front half of
  // completion).
  []
}

// Collect branches must form a coherent bundle (partial-collect-design.md:
// cells of one bundle, pairwise disjoint). `classifyCollect` already rejects
// two shapes — branches spanning different splits, and a multi-branch collect
// whose branches are not alt flows — so surface those as witnesses here. The
// hole it cannot see is a DUPLICATE alt (two branches for one alt): that keeps
// covered-count == branch-count, so it misclassifies as a full/partial case
// collect and would crash the case emitter looking for the uncovered alt.
// Checking distinctness here turns that crash into a witness.
let checkCoverage = (p: program): array<witness> => {
  let out: array<witness> = []
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | Collect({branches}) =>
      switch classifyCollect(branches) {
      | Malformed(msg) =>
        Array.push(out, {nodeId: n.id, rule: "coverage", message: "collect is malformed: " ++ msg})
      | CaseFull | CasePartial(_) => {
          let seen: Map.t<string, bool> = Map.make()
          branches->Array.forEach(b =>
            switch b.flow {
            | FlowPort(_, port) =>
              if Map.has(seen, port) {
                Array.push(
                  out,
                  {
                    nodeId: n.id,
                    rule: "coverage",
                    message: "case collect covers alt \"" ++ port ++ "\" more than once (branches must be pairwise disjoint)",
                  },
                )
              } else {
                Map.set(seen, port, true)
              }
            }
          )
        }
      | IterCollect => ()
      }
    | _ => ()
    }
  )
  out
}

// A per-iteration (flow-borne) value referenced from outside its flow
// (types-design.md; replaces the legacy compiler's memo-ancestor guard as a
// stated check). v0 checks the program boundary: a distinguished output is
// read outside every flow, so its context must be empty.
//
// TODO(types-design.md) for the general rule: every reference's context
// must be contained in its consumer's — for each collect branch, the
// value's context must sit within the branch's iterated chain. Today the
// interior cases are covered indirectly (alignment raises on incomparable
// merges; Codegen's memo-miss failwith backstops the rest); stating them
// here as witnesses is the fill-in.
let checkFlowBorne = (p: program): array<witness> => {
  let out: array<witness> = []
  p.outputs->Array.forEach(o =>
    try {
      let ctx = Context.valueContext(o.source)
      if Array.length(ctx) > 0 {
        Array.push(
          out,
          {
            nodeId: nodeOfValue(o.source).id,
            rule: "flow-borne",
            message: "output \"" ++
            o.name ++
            "\" reads a per-iteration value (context " ++
            Context.contextToString(ctx) ++ "); collect its flows first",
          },
        )
      }
    } catch {
    | Context.Incomparable(_) => () // alignment reports that clash
    }
  )
  out
}

let check = (p: program): array<witness> =>
  Array.flat([
    checkPortExists(p),
    checkWriteCount(p),
    checkAlignment(p),
    checkJoinAdjacency(p),
    checkProductivity(p),
    checkProvenance(p),
    checkCoverage(p),
    checkFlowBorne(p),
  ])

let witnessToString = (w: witness): string =>
  "node " ++ Int.toString(w.nodeId) ++ " [" ++ w.rule ++ "]: " ++ w.message
