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
//
// Stubbed with signatures (each names its design doc):
//   - join-adjacency  Join/Commute operands must be nesting-adjacent
//                     (lazy-stream-join-design.md).
//   - productivity    every cycle crosses a register pairing
//                     (first-class-ports-design.md, the pair section).
//   - provenance      cell-level disjointness / mixing-vs-time-travel
//                     classification (bundle-provenance-design.md).
//   - coverage        collect branches: cells of one bundle, pairwise
//                     disjoint (partial-collect-design.md).
//   - flow-borne      a per-iteration value port referenced from a body
//                     not inside its flow (types-design.md; subsumes the
//                     legacy honoured-limitations list).

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

let checkJoinAdjacency = (_p: program): array<witness> => {
  // TODO(lazy-stream-join-design.md): for each Join/Commute, inner's
  // exterior must end exactly at outer — read off Context.flowContext.
  []
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

let checkFlowBorne = (_p: program): array<witness> => {
  // TODO(types-design.md): a flow-borne value port (Program.flowBorne)
  // referenced from a consumer whose context does not contain that flow.
  // Replaces the legacy compiler's memo-ancestor guard as a stated check.
  []
}

let check = (p: program): array<witness> =>
  Array.flat([
    checkPortExists(p),
    checkWriteCount(p),
    checkAlignment(p),
    checkJoinAdjacency(p),
    checkProductivity(p),
    checkProvenance(p),
    checkFlowBorne(p),
  ])

let witnessToString = (w: witness): string =>
  "node " ++ Int.toString(w.nodeId) ++ " [" ++ w.rule ++ "]: " ++ w.message
