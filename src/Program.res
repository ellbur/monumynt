// The program of record — the ports-first representation.
//
// Built to the shape of plans/first-class-ports-design.md, with migration
// steps 2-3 (per-alt ports dissolving Branch, binary Join) already in place:
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
// diagrams-with-boundaries (a program here is one anonymous diagram: node set
// + named outputs). Each arrives with its own design round; the port model is
// what makes them local additions. (Aggregate/Disaggregate — struct
// construction and field projection — are now represented, as pure value
// nodes; they compile like an App. The textual surface for them is still owed.)
//
// The design record has since moved ahead of this file, and the planned
// additions now have ARCHITECTURE STUBS — modules that hold the staged
// types, the adopted decisions, and the settled rejections, each citing its
// design doc (see ARCHITECTURE.md, "Architecture stubs"). Planned `flowKind`
// rows: Stream (Stream.res), Async (Async.res), Var (Incremental.res), IO
// (Effects.res). Planned `kind` additions: EndWhen (Cut.res), Fail
// (Fail.res), Race / Settle / Paced / ReleaseHalf (Async.res), SelfOpen /
// PullSource (Stream.res), KeyedPartition (CollectFamily.res),
// SaturateRead / SaturateFeed (Saturation.res), Hole (Edit.res),
// SchematicSource (Property.res). Planned beside the node set: the boundary
// substrate — the remembered cut, call/link references, the op pair
// (Boundary.res; the {nodes, outputs} program is its degenerate top-level
// cut). Each stays staged in its stub until its emitter/check round, so the
// live matches here don't grow arms ahead of behaviour.

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
  // Aggregate: combine named field values into a struct
  // (visual-language-spec.md, "Aggregate"). A pure value node — fields are
  // ordinary value wires. Ports: value "value".
  | Aggregate({fields: array<(string, valueRef)>})
  // Disaggregate: the reverse — project a struct's fields, one value output
  // port per named field (visual-language-spec.md, "Disaggregate"). Ports:
  // one value port per field name. Sharing across projections is opt-in like
  // any node, but the fields are read off one node so a struct splits once.
  | Disaggregate({struct_: valueRef, fields: array<string>})

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
  | CaseFull // branches cover every cell of one case split
  | CasePartial(array<string>) // covered cells only; merged-flow port exists
  | Malformed(string)

let altsOfSplit = (n: node): option<array<string>> =>
  switch n.kind {
  | Uncollect({flowKind: Case({alts})}) => Some(alts)
  | _ => None
  }

// The CELLS of one bundle a branch flow spans, with the split they belong to
// (partial-collect-design.md, "Representation and compile": "keying by
// AlternativeName survives as the all-singletons display, but a branch may now
// reference a merged flow spanning several cells"; the set "is computed by
// walking, never stored").
//
//   - a case-alt flow port is the singleton `{A}` — the all-singletons instance;
//   - a partial collect's merged flow port is the union of its own branches',
//     which recurses, so a partial built over partials still names cells of the
//     one underlying split.
//
// `None` for anything that is not a bundle flow (a list/option axis, a join, a
// product): those flows terminate rather than merge.
let rec branchCells = (f: flowRef): option<(node, array<string>)> =>
  switch f {
  | FlowPort(n, port) =>
    switch n.kind {
    | Uncollect({flowKind: Case(_)}) => Some((n, [port]))
    | Collect({branches}) =>
      // Only a PARTIAL collect has a merged flow port at all; a covering one
      // hands back a plain value, and an iter collect leaves flow-land.
      switch classifyCollect(branches) {
      | CasePartial(covered) =>
        switch branches[0] {
        | Some({flow}) => branchCells(flow)->Option.map(((split, _)) => (split, covered))
        | None => None
        }
      | CaseFull | IterCollect | Malformed(_) => None
      }
    | _ => None
    }
  }

// A collect's coverage. Branches are cells of ONE bundle — single alt flows,
// merged flows of partial collects over that bundle, or a mix (the design's HTTP
// program: two singletons and a pair). Covering ⇒ a plain value at the parent
// (`CaseFull`); a proper subset ⇒ the merged flow output (`CasePartial`). The
// exhaustive case collect "is not a sibling construct to the partial collect; it
// is the covering configuration of the same node".
//
// A LONE branch on anything but a direct alt port terminates its flow instead of
// merging: an ordinary iter/filter chain, or the option-close lift of a merged
// flow ("collected alone"). Only a direct alt port makes a single branch a
// one-cell merge — the distinction that keeps `~pf -~> collect` a termination
// rather than a no-op re-merge of the same cells.
and classifyCollect = (branches: array<collectBranch>): coverage =>
  switch branches[0] {
  | None => Malformed("collect with no branches")
  | Some({flow: first}) =>
    let isDirectAlt = switch first {
    | FlowPort(t, _) => Option.isSome(altsOfSplit(t))
    }
    if Array.length(branches) === 1 && !isDirectAlt {
      IterCollect
    } else {
      switch branchCells(first) {
      | None => Malformed("multi-branch collect whose branches are not alt flows")
      | Some((target, _)) =>
        let alts = altsOfSplit(target)->Option.getOr([])
        let per = branches->Array.map(b =>
          switch branchCells(b.flow) {
          | Some((t, cs)) if t.id === target.id => Some(cs)
          | _ => None
          }
        )
        if per->Array.some(o => Option.isNone(o)) {
          Malformed("case collect mixes branches of different splits")
        } else {
          let covered = per->Array.reduce([], (acc, o) => Array.concat(acc, o->Option.getOr([])))
          if Array.length(covered) === Array.length(alts) {
            CaseFull
          } else {
            CasePartial(covered)
          }
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
  | Aggregate(_) => ["value"]
  | Disaggregate({fields}) => fields
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
  | Aggregate(_) | Disaggregate(_) => []
  }

// Is this value port flow-borne (per-iteration / per-alt — it only exists
// inside a body of its flow)? This is the property whose violation would
// otherwise surface as scattered `failwith`s in codegen; making it a
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
  | Aggregate({fields}) => {
      values: fields->Array.map(((_, v)) => v),
      flows: [],
      pairedReads: [],
    }
  | Disaggregate({struct_}) => {values: [struct_], flows: [], pairedReads: []}
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
  | Aggregate(_) => "Aggregate"
  | Disaggregate(_) => "Disaggregate"
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
    | Aggregate({fields}) =>
      "fields=[" ++ fields->Array.map(((k, v)) => k ++ "=" ++ vref(v))->Array.join(", ") ++ "]"
    | Disaggregate({struct_, fields}) =>
      "input=" ++ vref(struct_) ++ " fields=[" ++ fields->Array.join(", ") ++ "]"
    }
    Array.push(lines, num(n) ++ " " ++ kindName(n.kind) ++ " " ++ detail)
  })
  p.outputs->Array.forEach(o =>
    Array.push(lines, "out " ++ o.name ++ " = " ++ vref(o.source))
  )
  lines->Array.join("\n")
}

let equal = (a: program, b: program): bool => dump(a) === dump(b)
