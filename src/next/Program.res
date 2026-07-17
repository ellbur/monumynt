// The program of record — next-generation representation.
//
// This is the ports-first successor to src/Expr.res, built to the shape of
// plans/first-class-ports-design.md with migration steps 2-3 done from the
// start rather than staged:
//
//   - Every wire names a *port* of a node: `ValuePort(node, name)` /
//     `FlowPort(node, name)`. There is no Branch node (an alt's payload and
//     flow are ports of the case split itself) and no Joined/Filtered
//     wrapper stack (join is a binary node with two flow operands).
//   - The design vocabulary is used in code: Uncollect/Collect, not
//     Open/Close (the rename the compile-strategy doc schedules "with the
//     rebuild").
//   - A program is a NODE SET with distinguished outputs, not a root
//     expression — forced by Delay write halves being root-unreachable
//     (first-class-ports-design.md, "the program is a node set").
//   - The Delay pair (DelayRead / DelayWrite) is represented, as compiler
//     substrate. Representing it does NOT choose between the two
//     iteration-state surface candidates (iteration-with-state-design.md);
//     the pair is both candidates' result form.
//
// Provisional decisions made here (each cheap to revisit, recorded so they
// are decisions rather than accidents):
//
//   - Port names are strings at the representation level (spec-faithful,
//     printable in witnesses); nobody authors against them — Build.res's
//     typed handles are the authoring layer.
//   - Alt ports use the bare alt name on both the value and the flow side,
//     disambiguated by the ref sort (open question 1 of the ports doc; the
//     textual form's lean, its open question 6).
//   - Join is flow-only (no pass-through value ports) — the confirmed lean
//     of ports-doc open question 3; value crossings stay derived.
//   - The write half names its read by bare node reference, not a thread
//     port (the recorded naming/pairing question; either spelling works).
//   - Node ids are plain ints minted by the builder. Derived/inserted nodes
//     (the derive and complete passes) will need deterministic composite
//     ids ((host id, internal name), never a counter) — those stay
//     compile-internal and are keyed as strings, not represented here.
//
// Node kinds present but NOT yet compilable (see Codegen.res / Pipeline.res
// for what runs today): Commute, Cross, DelayRead, DelayWrite. They are in
// the representation so the printer, the checks, and authoring experiments
// can exercise them ahead of the compile catching up.
//
// Not represented yet (deliberately): stream/async/incremental flow kinds,
// race and concurrent-join barriers, partial-collect's None-port decision,
// Aggregate/Disaggregate, diagrams-with-boundaries (a program here is one
// anonymous diagram: node set + named outputs). Each arrives with its own
// design round; the port model is what makes them local additions.

type rec node = {id: int, kind: kind}

// A wire source: one output port of one node. Sharing is node identity —
// two refs to the same node's same port are the same wire source; refs
// themselves stay structural and untagged.
and valueRef = ValuePort(node, string)
and flowRef = FlowPort(node, string)

and flowKind =
  | List
  | Option
  // The discriminator is an ordinary value input (a wire, normally to a Lit
  // holding a JS function `(input) => {tag, value}`), not an embedded JsAst
  // payload — functions are values here.
  | Case({alts: array<string>, discriminator: valueRef})

and kind =
  | Lit(JsAst.expr)
  // fn is a wire too (usually to a Lit extern). Ports: value "value".
  | App({fn: valueRef, args: array<valueRef>})
  // Uncollect (design name; was Open). Ports:
  //   List/Option: value "element", flow "flow".
  //   Case:        value <alt> and flow <alt>, one pair per alt.
  // `nesting` is the spec's outerFlows ("open ... in ~L"): explicit outer
  // nesting when it is neither implied by the input's context nor left
  // under-committed for the complete pass.
  | Uncollect({flowKind: flowKind, input: valueRef, nesting: option<flowRef>})
  // Collect (was Close). One branch per consumed flow cell. A list/option/
  // filter collect has one branch; a case collect one branch per covered
  // alt (the alt is read off the branch's flow port name — no altName
  // field). Coverage is read off the cells (partial-collect-design.md):
  // full coverage ⇒ ports {value}; partial ⇒ {value} plus merged flow
  // "flow".
  | Collect({branches: array<collectBranch>})
  // Binary join (lazy-stream-join-design.md correction): absorbs `inner`'s
  // firings into `outer`. Filtering is join(list, case-alt flow) — no
  // separate Filter kind. Ports: flow "flow".
  | Join({outer: flowRef, inner: flowRef})
  // Swap two nesting-adjacent layers. Ports: flow "outer" (the flow that
  // was inner, now outermost) and flow "inner". Operand order is semantic.
  | Commute({outer: flowRef, inner: flowRef})
  // Product of two sibling (mutually invariant) flows
  // (product-flows-design.md). Stored oriented, read symmetric. Ports:
  // flow "flow". Compile target (point-indexed table) not built yet.
  | Cross({left: flowRef, right: flowRef})
  // Register read half: brings `init` in from outside the flow; "prev" is
  // the per-iteration tap. No flow outputs.
  | DelayRead({flow: flowRef, init: valueRef})
  // Register write half: the later wiring act as its own node (the ports
  // doc's "move the edge, not the node"). The write→read pairing is the
  // language's one iteration-boundary edge; the object graph stays a DAG.
  // "final" is the register's value after the flow completes (init if no
  // iteration ran).
  | DelayWrite({read: node, step: valueRef})

and collectBranch = {flow: flowRef, value: valueRef}

type output = {name: string, source: valueRef}

// The program of record: the node set (which may contain root-unreachable
// nodes — write halves, effect sinks) plus distinguished outputs.
type program = {nodes: array<node>, outputs: array<output>}

// --- Port inventories ---------------------------------------------------
//
// Per-kind and irregular by design (Commute has no value ports, DelayRead
// no flow ports); the one uniform question "does this kind have that port"
// is what the ref-validity check asks.

// Coverage classification for a Collect, read off its branch flows.
type coverage =
  | IterCollect // closes a list/option/join chain: single branch, not alt-flows
  | CaseFull // one branch per alt of one case split
  | CasePartial(array<string>) // covered alts only; merged-flow port exists
  | Malformed(string)

let altsOfSplit = (n: node): option<array<string>> =>
  switch n.kind {
  | Uncollect({flowKind: Case({alts})}) => Some(alts)
  | _ => None
  }

let classifyCollect = (branches: array<collectBranch>): coverage => {
  switch branches[0] {
  | None => Malformed("collect with no branches")
  | Some({flow: FlowPort(target, _)}) =>
    switch altsOfSplit(target) {
    | Some(alts) =>
      // Branches target alt flows of a case split: a case collect.
      let covered = branches->Array.filterMap(b =>
        switch b.flow {
        | FlowPort(t, p) if t.id === target.id => Some(p)
        | _ => None
        }
      )
      if Array.length(covered) !== Array.length(branches) {
        Malformed("case collect mixes branches of different splits")
      } else if Array.length(covered) === Array.length(alts) {
        CaseFull
      } else {
        CasePartial(covered)
      }
    | None =>
      if Array.length(branches) === 1 {
        IterCollect
      } else {
        Malformed("multi-branch collect whose branches are not alt flows")
      }
    }
  }
}

let valuePorts = (k: kind): array<string> =>
  switch k {
  | Lit(_) | App(_) => ["value"]
  | Collect(_) => ["value"]
  | Uncollect({flowKind: List | Option}) => ["element"]
  | Uncollect({flowKind: Case({alts})}) => alts
  | Join(_) | Commute(_) | Cross(_) => []
  | DelayRead(_) => ["prev"]
  | DelayWrite(_) => ["final"]
  }

let flowPorts = (k: kind): array<string> =>
  switch k {
  | Lit(_) | App(_) => []
  | Collect({branches}) =>
    switch classifyCollect(branches) {
    | CasePartial(_) => ["flow"] // the merged flow of the covered alts
    | _ => []
    }
  | Uncollect({flowKind: List | Option}) => ["flow"]
  | Uncollect({flowKind: Case({alts})}) => alts
  | Join(_) | Cross(_) => ["flow"]
  | Commute(_) => ["outer", "inner"]
  | DelayRead(_) | DelayWrite(_) => []
  }

// Is this value port flow-borne (per-iteration / per-alt — it only exists
// inside a body of its flow)? This is the property whose violation used to
// surface as scattered `failwith`s in the legacy compiler; making it a
// port-level fact is what lets Check state the time-travel / leakage rule.
let flowBorne = (k: kind, port: string): bool =>
  switch k {
  | Uncollect(_) => true // "element" or an alt payload
  | DelayRead(_) => port === "prev"
  | _ => false
  }

// --- Structural walking helpers ------------------------------------------

type nodeInputs = {
  values: array<valueRef>,
  flows: array<flowRef>,
  // The write half's read pairing — an edge, but not a port reference.
  pairedReads: array<node>,
}

let inputs = (n: node): nodeInputs =>
  switch n.kind {
  | Lit(_) => {values: [], flows: [], pairedReads: []}
  | App({fn, args}) => {
      values: Array.concat([fn], args),
      flows: [],
      pairedReads: [],
    }
  | Uncollect({flowKind, input, nesting}) => {
      values: switch flowKind {
      | Case({discriminator}) => [input, discriminator]
      | List | Option => [input]
      },
      flows: switch nesting {
      | Some(f) => [f]
      | None => []
      },
      pairedReads: [],
    }
  | Collect({branches}) => {
      values: branches->Array.map(b => b.value),
      flows: branches->Array.map(b => b.flow),
      pairedReads: [],
    }
  | Join({outer, inner}) | Commute({outer, inner}) => {
      values: [],
      flows: [outer, inner],
      pairedReads: [],
    }
  | Cross({left, right}) => {values: [], flows: [left, right], pairedReads: []}
  | DelayRead({flow, init}) => {values: [init], flows: [flow], pairedReads: []}
  | DelayWrite({read, step}) => {values: [step], flows: [], pairedReads: [read]}
  }

let nodeOfValue = (r: valueRef): node =>
  switch r {
  | ValuePort(n, _) => n
  }

let nodeOfFlow = (r: flowRef): node =>
  switch r {
  | FlowPort(n, _) => n
  }

// --- Canonical dump -------------------------------------------------------
//
// A stable, id-normalized rendering: nodes are renumbered by a DFS from the
// outputs (inputs before consumers), then any root-unreachable remainder in
// node-set order. Two programs with the same wiring dump identically no
// matter what order they were built in — this is the structural-equality
// surface the round-trip tests compare on, and a debugging view.

let kindName = (k: kind): string =>
  switch k {
  | Lit(_) => "Lit"
  | App(_) => "App"
  | Uncollect({flowKind: List}) => "Uncollect list"
  | Uncollect({flowKind: Option}) => "Uncollect option"
  | Uncollect({flowKind: Case(_)}) => "Uncollect case"
  | Collect(_) => "Collect"
  | Join(_) => "Join"
  | Commute(_) => "Commute"
  | Cross(_) => "Cross"
  | DelayRead(_) => "DelayRead"
  | DelayWrite(_) => "DelayWrite"
  }

let dump = (p: program): string => {
  let order: array<node> = []
  let seen: Map.t<int, int> = Map.make() // node id -> canonical index

  let rec visit = (n: node): unit =>
    if !Map.has(seen, n.id) {
      // Claim a slot before recursing? No — post-order: inputs first. Guard
      // against revisit via a pre-mark.
      Map.set(seen, n.id, -1)
      let ins = inputs(n)
      ins.values->Array.forEach(v => visit(nodeOfValue(v)))
      ins.flows->Array.forEach(f => visit(nodeOfFlow(f)))
      ins.pairedReads->Array.forEach(visit)
      Map.set(seen, n.id, Array.length(order))
      Array.push(order, n)
    } else if Map.get(seen, n.id) == Some(-1) {
      // A cycle in the object graph is impossible by construction (the
      // write half holds the back-edge); reaching here means corruption.
      failwith("Program.dump: cycle in object graph at node " ++ Int.toString(n.id))
    }

  p.outputs->Array.forEach(o => visit(nodeOfValue(o.source)))
  p.nodes->Array.forEach(visit)

  let num = (n: node): string =>
    switch Map.get(seen, n.id) {
    | Some(i) => "#" ++ Int.toString(i)
    | None => "#?"
    }
  let vref = (r: valueRef): string =>
    switch r {
    | ValuePort(n, port) => num(n) ++ "." ++ port
    }
  let fref = (r: flowRef): string =>
    switch r {
    | FlowPort(n, port) => num(n) ++ ".~" ++ port
    }

  let lines: array<string> = []
  order->Array.forEach(n => {
    let detail = switch n.kind {
    | Lit(js) => JsPrint.printExpr(js)
    | App({fn, args}) =>
      "fn=" ++ vref(fn) ++ " args=[" ++ args->Array.map(vref)->Array.join(", ") ++ "]"
    | Uncollect({flowKind, input, nesting}) =>
      let base = "input=" ++ vref(input)
      let base = switch flowKind {
      | Case({alts, discriminator}) =>
        base ++ " disc=" ++ vref(discriminator) ++ " alts=[" ++ alts->Array.join(", ") ++ "]"
      | List | Option => base
      }
      switch nesting {
      | Some(f) => base ++ " in " ++ fref(f)
      | None => base
      }
    | Collect({branches}) =>
      branches
      ->Array.map(b => fref(b.flow) ++ " : " ++ vref(b.value))
      ->Array.join("; ")
    | Join({outer, inner}) | Commute({outer, inner}) =>
      "outer=" ++ fref(outer) ++ " inner=" ++ fref(inner)
    | Cross({left, right}) => "left=" ++ fref(left) ++ " right=" ++ fref(right)
    | DelayRead({flow, init}) => "flow=" ++ fref(flow) ++ " init=" ++ vref(init)
    | DelayWrite({read, step}) => "read=" ++ num(read) ++ " step=" ++ vref(step)
    }
    Array.push(lines, num(n) ++ " " ++ kindName(n.kind) ++ " " ++ detail)
  })
  p.outputs->Array.forEach(o =>
    Array.push(lines, "out " ++ o.name ++ " = " ++ vref(o.source))
  )
  lines->Array.join("\n")
}

let equal = (a: program, b: program): bool => dump(a) === dump(b)
