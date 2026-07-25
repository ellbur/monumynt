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
//   - alignment       combining values from incomparable contexts, via
//                     Context's prefix-rule merge, CLASSIFIED into its two
//                     flavors (bundle-provenance-design.md): bundle mixing
//                     (sibling cells of one split — a hard error) vs time
//                     travel (unrelated opens — completable). The classifier
//                     walks the two paths to their first divergent step.
//   - join-adjacency  Join/Commute operands must be nesting-adjacent
//                     (lazy-stream-join-design.md).
//   - invariance      Cross operands must be mutually invariant — neither
//                     axis's firings vary with the other's element
//                     (product-flows-design.md, the Cross round's first step).
//                     Consumes Annotate's flow-variable sets.
//   - flow-borne      a per-iteration value escaping its flow (types-design.md):
//                     to a program output (context must be empty) or read by a
//                     collect branch that does not iterate the value's flow (the
//                     general interior rule — exact for element / alt-payload
//                     interiors; Join/Commute/Cross interiors defer to the poset
//                     round).
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
//   - provenance      the mixing-vs-time-travel classification folded into
//                     alignment (above); what remains stubbed is the deferred
//                     cell-set / subset-lattice remainder, which needs the
//                     non-tree context model of the Cross round
//                     (bundle-provenance-design.md, "merged branches as cell
//                     sets").

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

// --- alignment + the mixing / time-travel classification ---------------------
//
// bundle-provenance-design.md, "one check, two clash flavors": when two flow
// contexts are incomparable, walk them to their last common context and look at
// the first divergent pair of steps.
//
//   - Both steps are cells of ONE case split (same node, different alt ports) →
//     BUNDLE MIXING. The two values live in mutually exclusive cells that never
//     coexist, so no execution produces both. A hard error (siblings may meet
//     only at a collect — "the one door").
//   - Anything else (two independent opens, or two different splits) → TIME
//     TRAVEL. Sibling contexts with no correspondence between their firings.
//     Completable: completion inserts a Cross (product-flows-design.md); Check
//     only witnesses it.
//
// This is the refinement bundle-provenance-design.md folds into the alignment
// step ("not a second check beside that one; the same check with the property
// refined") — so the two flavors live here, and checkProvenance carries only
// the deferred cell-set remainder.

type clash =
  | Mixing({split: node, cellA: string, cellB: string})
  | TimeTravel({openA: flowRef, openB: flowRef})

let classifyClash = (left: array<flowRef>, right: array<flowRef>): clash => {
  // Longest common prefix by flow key. Incomparable ⇒ neither path is a prefix
  // of the other, so a divergent step exists on each side at index `k`.
  let k = ref(0)
  let common = () =>
    switch (left[k.contents], right[k.contents]) {
    | (Some(l), Some(r)) => Context.flowKey(l) === Context.flowKey(r)
    | _ => false
    }
  while common() {
    k := k.contents + 1
  }
  switch (left[k.contents], right[k.contents]) {
  | (Some(FlowPort(na, pa)), Some(FlowPort(nb, pb))) if na.id === nb.id =>
    switch altsOfSplit(na) {
    | Some(_) => Mixing({split: na, cellA: pa, cellB: pb})
    | None => TimeTravel({openA: FlowPort(na, pa), openB: FlowPort(nb, pb)})
    }
  | (Some(l), Some(r)) => TimeTravel({openA: l, openB: r})
  | _ =>
    // Unreachable: an incomparable pair always diverges before either path ends.
    failwith("Check.classifyClash: contexts are comparable — merge should not have raised")
  }
}

let checkAlignment = (p: program): array<witness> => {
  let out: array<witness> = []
  // The program's constructed Cross products — the index that turns a sibling
  // combine from a time-travel gap into a well-formed product combine
  // (product-flows-design.md, "The context model").
  let products = Context.productsIndex(p)

  let mixingWitness = (n: node, split: node, cellA: string, cellB: string) =>
    // Bundle mixing is untouched by Cross: sibling cells never coexist, so no
    // product can host the combine (product-flows-design.md, "bundle mixing —
    // untouched, as ever; the missing fact there is an execution").
    Array.push(
      out,
      {
        nodeId: n.id,
        rule: "bundle-mixing",
        message: "values live in mutually exclusive cells \"" ++
        cellA ++
        "\" and \"" ++
        cellB ++
        "\" of case split node " ++
        Int.toString(split.id) ++
        "; no execution produces both (sibling cells meet only at a collect)",
      },
    )

  let timeTravelWitness = (n: node, openA: flowRef, openB: flowRef) =>
    Array.push(
      out,
      {
        nodeId: n.id,
        rule: "time-travel",
        message: "combining values from unrelated flows " ++
        Context.flowKey(openA) ++
        " and " ++
        Context.flowKey(openB) ++
        " with no correspondence between their firings (completion inserts a Cross)",
      },
    )

  p.nodes->Array.forEach(n => {
    // Probe each output port: computing a port's context is what merges the
    // input contexts (an App's args, a Cross's operands), so this is where
    // incomparability surfaces. A value port is checked FULL-SPAN — the linear
    // merge raises on the first sibling pair, so it admits a value like
    // `f(x, y, z)` on the {X,Y} pair even when no product covers all three axes;
    // the poset-aware recomputation reaches every combine and witnesses the
    // uncovered one (checkAlignment's full-span re-verification — the case that
    // previously slipped through Check and only declined at Codegen).
    valuePorts(n.kind)->Array.forEach(port =>
      switch Context.valueContext(ValuePort(n, port)) {
      | _ => ()
      | exception Context.Incomparable({left, right, where: _}) =>
        switch classifyClash(left, right) {
        | Mixing({split, cellA, cellB}) => mixingWitness(n, split, cellA, cellB)
        | TimeTravel({openA, openB}) =>
          // Full-span: does the WHOLE value have a poset home? If a constructed
          // Cross covers every combine it reaches, admit; otherwise it is a
          // (completable) time-travel gap — including the under-covered n-ary
          // consumer, whose first pair IS covered but whose full span is not.
          switch Context.posetValueContext(~products, ValuePort(n, port)) {
          | _ => () // admitted — the full span lies in constructed products
          | exception Poset.Incomparable(_, _) => timeTravelWitness(n, openA, openB)
          // A deeper poset case (an operand exterior that is itself a product)
          // is beyond this pass; fall back to the single-pair check, unchanged.
          | exception Context.Incomparable(_) =>
            switch Poset.merge(~products, Context.pathToPoset(left), Context.pathToPoset(right)) {
            | _ => ()
            | exception Poset.Incomparable(_, _) => timeTravelWitness(n, openA, openB)
            }
          }
        }
      }
    )
    // Flow ports (a Cross's product output) merge their operands pairwise; the
    // single-pair product check is exact for them.
    flowPorts(n.kind)->Array.forEach(port =>
      switch Context.flowContext(FlowPort(n, port)) {
      | _ => ()
      | exception Context.Incomparable({left, right, where: _}) =>
        switch classifyClash(left, right) {
        | Mixing({split, cellA, cellB}) => mixingWitness(n, split, cellA, cellB)
        | TimeTravel({openA, openB}) =>
          switch Poset.merge(~products, Context.pathToPoset(left), Context.pathToPoset(right)) {
          | _ => () // admitted — a constructed Cross covers this combine
          | exception Poset.Incomparable(_, _) => timeTravelWitness(n, openA, openB)
          }
        }
      }
    )
  })
  out
}

// --- stubs -------------------------------------------------------------------
//
// Rules for constructs that are planned but not yet represented live with
// their construct's architecture stub, each typed against `witness` so they
// join this pass's result when wired in via Pipeline: OrderDemand.res (the
// adopted order-demand rule for Delays — a register's driving flow must OWN
// a total order), Fail.res (discharge exhaustiveness against the derived
// endings inventory), Cut.res (stop-operand admissibility), Stream.res
// (stack well-formedness), Async.res (race pair coherence; no register in
// the sever->settle interior), Boundary.res (reusability; the measure
// discipline), Effects.res (IO flows join back), Property.res (the
// demand/offer propagation these rules generalise into).

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
        // The interior the inner must open at is the outer flow's INTERIOR, which
        // for a Join is its flattened interior (through stacked joins), not a
        // single `[outer]` layer — otherwise a nested flatten (flatten a
        // list-of-lists, then filter/flatten again) is wrongly rejected.
        let expected = Context.flowInterior(outer)
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

// Cross's demand: the two operands must be mutually invariant
// (product-flows-design.md, "The construct"). A violation means one axis's
// firings vary with the other's element — the nesting is dependent, not a
// product, so it has no transpose and cannot be crossed. This is the front
// half of the Cross round (its "smallest first step" 1): the demand is
// checkable ahead of the whole-table emitter, so an ill-formed Cross is
// witnessed here rather than mis-compiled once the poset emitter lands. The
// flow-variable machinery it consumes lives in Annotate (the invariance fact
// is an annotate-pass fact; Check calls it directly, as the pipeline permits).
let checkCross = (p: program): array<witness> => {
  let out: array<witness> = []
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | Cross({left, right}) =>
      switch Annotate.crossViolation(left, right) {
      | Some(axisKey) =>
        Array.push(
          out,
          {
            nodeId: n.id,
            rule: "invariance",
            message: "cross operands are not mutually invariant: one axis's firings vary " ++
            "with flow " ++
            axisKey ++
            " (the other operand's element), so the nesting is dependent, not a product — " ++
            "no transpose exists to cross",
          },
        )
      | None => ()
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
  // The mixing-vs-time-travel classification (bundle-provenance-design.md, "one
  // check, two clash flavors") now lives in checkAlignment — it is "the same
  // check with the property refined," so it belongs at the point the clash
  // surfaces, not in a second pass. What remains here is the DEFERRED cell-set
  // remainder (the poset round): a context path whose bundle step carries a
  // *set* of cells (partial collect's `{A, B}`), where comparability is subset
  // containment. The not-≤ branch splits by the MEET (bundle-provenance-
  // design.md, "Revision: overlap is incorporate, not a clash"): a non-empty
  // meet (`{A,B}` vs `{B,C}` ⇒ `{B}`) is an inferred incorporate to that meet,
  // NOT a clash; only a disjoint (empty) meet is bundle mixing. That needs the
  // non-tree context model the Cross emitter brings plus completion's
  // incorporate insertion, so it stays stubbed until products land
  // (ARCHITECTURE.md, "the poset round").
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
// (types-design.md; the memo-ancestor placement guard restated as an explicit
// check). Two rules, one property — "every reference's context must be
// contained in its consumer's":
//
//   - the PROGRAM BOUNDARY: a distinguished output is read outside every
//     flow, so its context must be empty.
//   - the general INTERIOR rule: a collect branch consumes its value at the
//     interior of the flow it iterates, so the value's context must be a
//     prefix of (contained in) that interior. A value borne on a flow the
//     collect does NOT iterate — a sibling alt's payload, an element of an
//     unrelated open — cannot be read at the branch. This is the memo-ancestor
//     miss, which Codegen surfaces as a "flow-borne port reached outside its
//     flow" failwith ("Check's flow-borne rule should have witnessed this");
//     stating it here turns that crash into a
//     witness.
//
// The interior is computed only where it is EXACT: a list/option element or a
// case alt payload — the branch's flow port targets an Uncollect, and the
// interior is that flow's own layer over its exterior. A branch that iterates a
// Join / Commute / Cross flow descends into the poset round (the interior lives
// deeper than the join's own layer); `branchInterior` returns None there and
// the branch is left to the indirect coverage (alignment + the codegen
// backstop), per ARCHITECTURE.md's "covered indirectly" note.
let branchInterior = (flow: flowRef): option<array<flowRef>> =>
  switch flow {
  | FlowPort(n, _) =>
    switch n.kind {
    | Uncollect(_) => Some(Array.concat(Context.flowContext(flow), [flow]))
    | _ => None
    }
  }

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
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | Collect({branches}) =>
      branches->Array.forEach(b =>
        switch branchInterior(b.flow) {
        | None => () // Join/Commute/Cross-borne interior — the poset round
        | Some(interior) =>
          try {
            let vctx = Context.valueContext(b.value)
            if !Context.isPrefix(vctx, interior) {
              Array.push(
                out,
                {
                  nodeId: n.id,
                  rule: "flow-borne",
                  message: "collect branch reads a value borne in context " ++
                  Context.contextToString(vctx) ++
                  " but iterates " ++
                  Context.contextToString(interior) ++
                  "; the value lives on a flow this collect does not iterate",
                },
              )
            }
          } catch {
          | Context.Incomparable(_) => () // alignment reports that clash
          }
        }
      )
    | _ => ()
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
    checkCross(p),
    checkProductivity(p),
    checkProvenance(p),
    checkCoverage(p),
    checkFlowBorne(p),
  ])

let witnessToString = (w: witness): string =>
  "node " ++ Int.toString(w.nodeId) ++ " [" ++ w.rule ++ "]: " ++ w.message
