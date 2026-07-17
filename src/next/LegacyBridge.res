// DISPOSABLE scaffolding: compile the new representation by translating it
// into the legacy one (src/Expr.res) and running the legacy compiler.
//
// Why it exists: the implementation-strategy sequencing is ports migration
// first, compiler rebuild second. This bridge is the migration bridge —
// it lets the new representation, the text surface, and the checks be
// exercised end-to-end (build/parse -> check -> JS -> eval) before
// Codegen.res is written. It must never grow features: anything the legacy
// compiler can't express (registers, commute, cross, explicit nesting,
// partial collects, multi-value-port externs) fails loudly here and waits
// for the rebuild. When Codegen lands, this file is deleted and the legacy
// modules follow.
//
// Translation notes:
//   - Sharing is preserved by memoising per node id (and per (split, alt)
//     for the Branch satellite nodes the legacy representation needs).
//   - App fn / case discriminator must resolve to Lit nodes: the legacy
//     kinds embed JsAst payloads where the new representation has wires.
//   - Join(outer, inner) drops its outer operand: the legacy wrapper stack
//     re-derives it from the input chain. Filter = Join with a case-alt
//     inner = legacy `Filtered`; anything else = legacy `Joined`.

open Program

type ctx = {
  exprs: Map.t<int, Expr.handle>,
  branchNodes: Map.t<string, Expr.handle>, // "splitId:alt" -> legacy Branch
}

let makeCtx = (): ctx => {exprs: Map.make(), branchNodes: Map.make()}

let litPayload = (r: valueRef, what: string): JsAst.expr =>
  switch nodeOfValue(r).kind {
  | Lit(js) => js
  | k =>
    failwith(
      "LegacyBridge: " ++
      what ++
      " must be a Lit under the bridge (got " ++
      kindName(k) ++ ") — computed functions wait for the Codegen rebuild",
    )
  }

let rec exprOf = (c: ctx, n: node): Expr.handle =>
  switch Map.get(c.exprs, n.id) {
  | Some(h) => h
  | None => {
      let h = switch n.kind {
      | Lit(js) => Expr.lit(js)
      | App({fn, args}) =>
        Expr.app(litPayload(fn, "App fn"), args->Array.map(v => valueOf(c, v)))
      | Uncollect({nesting: Some(_)}) =>
        failwith(
          "LegacyBridge: explicit `in` nesting not supported (legacy infers nesting from the input); wait for Codegen",
        )
      | Uncollect({flowKind: List, input}) =>
        Expr.open_(Expr.ListIter, valueOf(c, input))
      | Uncollect({flowKind: Option, input}) =>
        Expr.open_(Expr.OptionIter, valueOf(c, input))
      | Uncollect({flowKind: Case({alts, discriminator}), input}) =>
        Expr.open_(
          Expr.CaseSplit({alts, discriminator: litPayload(discriminator, "discriminator")}),
          valueOf(c, input),
        )
      | Collect({branches}) => collectOf(c, branches)
      | Join(_) | Commute(_) | Cross(_) =>
        failwith("LegacyBridge: flow node reached as a value — ill-formed program")
      | DelayRead(_) | DelayWrite(_) =>
        failwith("LegacyBridge: registers are not compilable yet (Codegen phase 6)")
      }
      Map.set(c.exprs, n.id, h)
      h
    }
  }

and valueOf = (c: ctx, r: valueRef): Expr.valueRef =>
  switch r {
  | ValuePort(n, port) =>
    switch n.kind {
    | Uncollect({flowKind: Case(_)}) => branchOf(c, n, port).value
    | _ => exprOf(c, n).value // "value" / "element" are the legacy single port
    }
  }

// The legacy Branch satellite for a (split, alt) pair — one per pair, so
// every use site shares one binding, mirroring the port-memo the ports doc
// describes.
and branchOf = (c: ctx, split: node, alt: string): Expr.handle => {
  let key = Int.toString(split.id) ++ ":" ++ alt
  switch Map.get(c.branchNodes, key) {
  | Some(h) => h
  | None => {
      let splitH = exprOf(c, split)
      let h = Expr.branch_(Expr.NodeFlow(splitH.node), alt)
      Map.set(c.branchNodes, key, h)
      h
    }
  }
}

and flowOf = (c: ctx, r: flowRef): Expr.flowRef =>
  switch r {
  | FlowPort(n, port) =>
    switch n.kind {
    | Uncollect({flowKind: List | Option}) => Expr.NodeFlow(exprOf(c, n).node)
    | Uncollect({flowKind: Case(_)}) => Expr.NodeFlow(branchOf(c, n, port).node)
    | Join({inner}) =>
      // Filter = join whose inner operand is a case-alt flow.
      switch inner {
      | FlowPort(t, altPort) =>
        switch t.kind {
        | Uncollect({flowKind: Case(_)}) =>
          Expr.Filtered(Expr.NodeFlow(branchOf(c, t, altPort).node))
        | _ => Expr.Joined(flowOf(c, inner))
        }
      }
    | Commute(_) => failwith("LegacyBridge: commute is not compilable yet (streams round)")
    | Cross(_) => failwith("LegacyBridge: cross is not compilable yet (product round)")
    | _ =>
      failwith("LegacyBridge: flow ref into " ++ kindName(n.kind) ++ " port " ++ port)
    }
  }

and collectOf = (c: ctx, branches: array<collectBranch>): Expr.handle =>
  switch classifyCollect(branches) {
  | IterCollect =>
    switch branches[0] {
    | Some({flow, value}) => Expr.close_(flowOf(c, flow), valueOf(c, value))
    | None => failwith("LegacyBridge: empty collect")
    }
  | CaseFull =>
    Expr.caseClose(
      branches->Array.map(b =>
        switch b.flow {
        | FlowPort(_, alt) =>
          ({
            altName: Some(alt),
            flow: flowOf(c, b.flow),
            value: valueOf(c, b.value),
          }: Expr.closeBranch)
        }
      ),
    )
  | CasePartial(_) =>
    failwith("LegacyBridge: partial collect lands after the checks round (phase 7)")
  | Malformed(msg) => failwith("LegacyBridge: malformed collect: " ++ msg)
  }

// Translate one distinguished output's subgraph. The ctx may be shared
// across outputs of one program so legacy node identity mirrors new node
// identity; each output still compiles to its own IIFE (single-module
// multi-output compilation is the rebuild's job).
let outputRoot = (c: ctx, p: program, name: string): Expr.handle =>
  switch p.outputs->Array.find(o => o.name === name) {
  | Some(o) => exprOf(c, nodeOfValue(o.source))
  | None => failwith("LegacyBridge: no output named " ++ name)
  }
