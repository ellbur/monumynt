// Printer: Program.program -> text (textual-representation-design.md,
// implementation path step 1).
//
// This is the printer's first PRETTY round (ARCHITECTURE.md worklist item 4,
// "chain compression + taps"). v0 was total but verbose — one named forward
// statement per node. This round recovers the postfix-chain form the textual
// design is written in: single-consumer runs fuse into `->`/`-~>` chains, the
// implicit flow stack drops flow names that a chain opens and closes itself,
// and single-use data literals inline into the stage that consumes them. It
// stays TOTAL (an unfused node always has its named-statement fallback) and,
// by construction, round-trips — every emitted form reparses to identical
// wiring (the round-trip test is the spec).
//
// The compression decisions, each conservative and revisitable (the design
// doc calls the implicitness thresholds an open question, so this errs toward
// keeping names rather than dropping them):
//
//   - A DATA literal (number / string / array / `js`) with exactly one use
//     that is not an application function, not a split discriminator, and not
//     an output source inlines at its use site (its `name = …` line is gone).
//     Function and discriminator literals stay named — they read better named,
//     and a name is the only spelling an App-fn / split-disc stage accepts.
//   - A value with a single consuming node is CHAIN-INTERNAL: it flows into
//     the next stage as the running topic and is never named. A value that
//     fans out (≥2 uses), is an output, or feeds a standalone construct is a
//     JUNCTION and gets a name; each consumer starts a fresh chain from it.
//     (Fan-out via a name desugars exactly as a tap would — P8 — so naming is
//     the total, round-tripping stand-in for the tap surface, which is a later
//     round.)
//   - A list/option flow is IMPLICIT (opened with no `~name`, closed by a bare
//     `collect` that reseeds the stack from the value's context) iff every one
//     of its consumers is an iter-collect that closes it as the innermost open
//     flow. Otherwise it is NAMED: its uncollect binds `~name` and every
//     consumer references it. Join/commute/cross operands, a delay's flow, an
//     explicit `in` nesting, and a partial collect's merged flow are always
//     named (they are referenced by standalone statements, which spell flows
//     by name).
//
// Deliberately still deferred to a later round (kept out to keep this one
// focused): junction TAPS (`|`) — named fan-out is the total stand-in; bare
// `join` in a chain (joins print as the standalone `join into` form); derived
// indentation by flow depth and the span lint; `+` completion lines. Forms the
// printer emits that are still ahead of the parser (they print so the
// constructs can be seen): `commute out of` / `cross with` standalone forms.

open Program

@val external jsonStringify: string => string = "JSON.stringify"

// --- naming ------------------------------------------------------------------

type namer = {
  names: Map.t<string, string>, // "nodeId:port" or "node:nodeId" -> name
  mutable counter: int,
}

let portKey = (n: node, port: string): string => Int.toString(n.id) ++ ":" ++ port
let nodeKey = (n: node): string => "node:" ++ Int.toString(n.id)

// Nodes whose refs print as projections off a node name.
let namedAsNode = (n: node): bool =>
  switch n.kind {
  | Uncollect({flowKind: Case(_)}) | Commute(_) => true
  | _ => false
  }

let fresh = (nm: namer, prefix: string): string => {
  nm.counter = nm.counter + 1
  prefix ++ Int.toString(nm.counter)
}

let nodeName = (nm: namer, n: node): string =>
  switch Map.get(nm.names, nodeKey(n)) {
  | Some(s) => s
  | None => {
      let prefix = switch n.kind {
      | Uncollect({flowKind: Case(_)}) => "cs"
      | Commute(_) => "c"
      | _ => "n"
      }
      let s = fresh(nm, prefix)
      Map.set(nm.names, nodeKey(n), s)
      s
    }
  }

let portName = (nm: namer, n: node, port: string, prefix: string): string =>
  switch Map.get(nm.names, portKey(n, port)) {
  | Some(s) => s
  | None => {
      let s = fresh(nm, prefix)
      Map.set(nm.names, portKey(n, port), s)
      s
    }
  }

// --- literal rendering ----------------------------------------------------------

let rec litIsLeaf = (e: JsAst.expr): bool =>
  switch e {
  | ENum(_) | EStr(_) => true
  | EArray(elems) =>
    elems->Array.every(el =>
      switch el {
      | AElem(inner) => litIsLeaf(inner)
      | _ => false
      }
    )
  | _ => false
  }

let litText = (e: JsAst.expr): string =>
  switch e {
  | ERaw(code) => "js " ++ jsonStringify(code)
  | _ =>
    if litIsLeaf(e) {
      JsPrint.printExpr(e)
    } else {
      // Structured payloads round-trip through the escape hatch. (They
      // come back as ERaw — the payload's printed JS is the identity that
      // survives, which is fine for an escape hatch.)
      "js " ++ jsonStringify(JsPrint.printExpr(e))
    }
  }

// --- the print --------------------------------------------------------------

let print = (p: program): string => {
  let nm = {names: Map.make(), counter: 0}

  // Emission order: post-order DFS from the outputs, then any remainder. Every
  // input precedes its node, so a name is always defined before it is used —
  // the invariant the resolver needs. FLOWS are visited before values so a
  // flow-defining node (a standalone join) precedes the value chain that fuses
  // its collect: without this, fusing a `-~> collect ~jN` into its value chain
  // would emit the reference before the `=> ~jN` binder.
  let order: array<node> = []
  let seen: Map.t<int, bool> = Map.make()
  let rec visit = (n: node): unit =>
    if !Map.has(seen, n.id) {
      Map.set(seen, n.id, true)
      let ins = inputs(n)
      ins.flows->Array.forEach(f => visit(nodeOfFlow(f)))
      ins.values->Array.forEach(v => visit(nodeOfValue(v)))
      ins.pairedReads->Array.forEach(visit)
      Array.push(order, n)
    }
  p.outputs->Array.forEach(o => visit(nodeOfValue(o.source)))
  p.nodes->Array.forEach(visit)

  // --- use analysis: value use counts, sole node consumers, flow consumers,
  //     and the "function / discriminator / output" positions that force a
  //     literal to stay named. ------------------------------------------------
  let vUse: Map.t<string, int> = Map.make() // value port key -> #references (incl. outputs)
  let vCons: Map.t<string, array<node>> = Map.make() // value port key -> consuming nodes
  let fCons: Map.t<string, array<node>> = Map.make() // flow port key -> consuming nodes
  let fnLit: Map.t<int, bool> = Map.make() // lit node id used as an App fn
  let discNode: Map.t<int, bool> = Map.make() // node id used as a split discriminator
  let outSrc: Map.t<string, bool> = Map.make() // value port key that is an output source

  let bumpV = (r: valueRef, consumer: option<node>): unit =>
    switch r {
    | ValuePort(n, port) => {
        let k = portKey(n, port)
        Map.set(vUse, k, Map.get(vUse, k)->Option.getOr(0) + 1)
        switch consumer {
        | Some(c) => {
            let a = switch Map.get(vCons, k) {
            | Some(a) => a
            | None => {
                let a: array<node> = []
                Map.set(vCons, k, a)
                a
              }
            }
            Array.push(a, c)
          }
        | None => ()
        }
      }
    }
  let addFCons = (r: flowRef, consumer: node): unit =>
    switch r {
    | FlowPort(n, port) => {
        let k = portKey(n, port)
        let a = switch Map.get(fCons, k) {
        | Some(a) => a
        | None => {
            let a: array<node> = []
            Map.set(fCons, k, a)
            a
          }
        }
        Array.push(a, consumer)
      }
    }

  p.nodes->Array.forEach(n => {
    switch n.kind {
    | App({fn, args}) => {
        switch fn {
        | ValuePort(fnNode, _) =>
          switch fnNode.kind {
          | Lit(_) => Map.set(fnLit, fnNode.id, true)
          | _ => ()
          }
        }
        bumpV(fn, Some(n))
        args->Array.forEach(a => bumpV(a, Some(n)))
      }
    | Uncollect({flowKind, input, nesting}) => {
        bumpV(input, Some(n))
        switch flowKind {
        | Case({discriminator}) => {
            bumpV(discriminator, Some(n))
            Map.set(discNode, nodeOfValue(discriminator).id, true)
          }
        | List | Option => ()
        }
        switch nesting {
        | Some(f) => addFCons(f, n)
        | None => ()
        }
      }
    | Collect({branches}) =>
      branches->Array.forEach(b => {
        bumpV(b.value, Some(n))
        addFCons(b.flow, n)
      })
    | Join({outer, inner}) | Commute({outer, inner}) => {
        addFCons(outer, n)
        addFCons(inner, n)
      }
    | Cross({left, right}) => {
        addFCons(left, n)
        addFCons(right, n)
      }
    | DelayRead({flow, init}) => {
        addFCons(flow, n)
        bumpV(init, Some(n))
      }
    | DelayWrite({step}) => bumpV(step, Some(n))
    | Lit(_) => ()
    }
  })
  p.outputs->Array.forEach(o => {
    bumpV(o.source, None)
    switch o.source {
    | ValuePort(n, port) => Map.set(outSrc, portKey(n, port), true)
    }
  })

  // Pre-claim output names for their source ports so the defining statement
  // binds the user-visible name directly.
  p.outputs->Array.forEach(o =>
    switch o.source {
    | ValuePort(n, port) =>
      if !namedAsNode(n) && !Map.has(nm.names, portKey(n, port)) {
        Map.set(nm.names, portKey(n, port), o.name)
      }
    }
  )

  // --- decisions --------------------------------------------------------------

  // A data literal that inlines at its (single) use site.
  let inlineLit = (n: node): bool =>
    switch n.kind {
    | Lit(_) =>
      Map.get(vUse, portKey(n, "value"))->Option.getOr(0) === 1 &&
      !Map.has(fnLit, n.id) &&
      !Map.has(discNode, n.id) &&
      !Map.has(outSrc, portKey(n, "value"))
    | _ => false
    }

  let ctxOf = (r: valueRef): array<flowRef> =>
    try Context.valueContext(r) catch {
    | Context.Incomparable(_) => [] // ill-formed; Check witnesses it, printer stays total
    }
  let innermost = (r: valueRef): option<flowRef> => {
    let c = ctxOf(r)
    c[Array.length(c) - 1]
  }

  // A list/option flow that needs no `~name`: opened and closed implicitly,
  // every consumer a bare iter-collect on it as the innermost open flow.
  let implicitFlow = (f: flowRef): bool =>
    switch f {
    | FlowPort(u, "flow") =>
      switch u.kind {
      | Uncollect({flowKind: List | Option}) => {
          let cons = Map.get(fCons, portKey(u, "flow"))->Option.getOr([])
          Array.length(cons) >= 1 &&
          cons->Array.every(c =>
            switch c.kind {
            | Collect({branches}) =>
              switch classifyCollect(branches) {
              | IterCollect =>
                switch branches[0] {
                | Some({flow, value}) =>
                  Context.flowKey(flow) === Context.flowKey(f) &&
                  (switch innermost(value) {
                  | Some(inm) => Context.flowKey(inm) === Context.flowKey(f)
                  | None => false
                  })
                | None => false
                }
              | _ => false
              }
            | _ => false
            }
          )
        }
      | _ => false
      }
    | _ => false
    }

  let sameValue = (a: valueRef, b: valueRef): bool =>
    switch (a, b) {
    | (ValuePort(na, pa), ValuePort(nb, pb)) => na.id === nb.id && pa === pb
    }

  // The single consuming node of a value, when the value has exactly one use
  // and that use is a node (not an output) — the chain-continuation link.
  let soleNodeConsumer = (r: valueRef): option<node> =>
    switch r {
    | ValuePort(n, port) =>
      let k = portKey(n, port)
      if Map.get(vUse, k)->Option.getOr(0) === 1 {
        switch Map.get(vCons, k) {
        | Some([c]) => Some(c)
        | _ => None
        }
      } else {
        None
      }
    }

  // --- reference rendering ----------------------------------------------------

  let valueName = (r: valueRef): string =>
    switch r {
    | ValuePort(n, port) =>
      if namedAsNode(n) {
        nodeName(nm, n) ++ "." ++ port
      } else {
        let prefix = switch n.kind {
        | Uncollect(_) => "e"
        | DelayRead(_) => "d"
        | DelayWrite(_) => "w"
        | _ => "n"
        }
        portName(nm, n, port, prefix)
      }
    }

  // A term in source / argument / discriminator / init position: the inlined
  // literal text when the target inlines, otherwise the value's name.
  let termOf = (r: valueRef): string =>
    switch r {
    | ValuePort(n, _) =>
      switch n.kind {
      | Lit(js) if inlineLit(n) => litText(js)
      | _ => valueName(r)
      }
    }

  let flowName = (r: flowRef): string =>
    switch r {
    | FlowPort(n, port) =>
      if namedAsNode(n) {
        nodeName(nm, n) ++ "." ++ port
      } else {
        let prefix = switch n.kind {
        | Join(_) => "j"
        | Cross(_) => "x"
        | Collect(_) => "pf" // a partial collect's merged flow
        | _ => "f"
        }
        portName(nm, n, port, prefix)
      }
    }

  // --- emission ---------------------------------------------------------------

  let lines: array<string> = []
  let emitted: Map.t<int, bool> = Map.make()
  let mark = (n: node) => Map.set(emitted, n.id, true)

  // Walk a value chain forward from `cur`, appending stage strings, until the
  // running value fans out / ends / meets a non-chain construct. Returns the
  // final value ref (to be named by a binder). Split is a terminal stage: it
  // yields a case-split handle, so it closes the value chain with a `=> csN`.
  let rec chainForward = (cur: valueRef, stages: array<string>): (valueRef, option<string>) =>
    switch soleNodeConsumer(cur) {
    | Some(c) if !Map.has(emitted, c.id) =>
      switch c.kind {
      | App({fn, args})
        if Array.length(args) >= 1 &&
        (switch args[0] {
        | Some(a0) => sameValue(a0, cur)
        | None => false
        }) => {
          // cur is the topic (first arg); any further args are extras.
          let extras = args->Array.slice(~start=1)
          let call = if Array.length(extras) === 0 {
            "-> " ++ termOf(fn)
          } else {
            "-> " ++ termOf(fn) ++ "(" ++ extras->Array.map(termOf)->Array.join(", ") ++ ")"
          }
          Array.push(stages, call)
          mark(c)
          chainForward(ValuePort(c, "value"), stages)
        }
      | Uncollect({flowKind: List | Option, input, nesting: None})
        if sameValue(input, cur) && implicitFlow(FlowPort(c, "flow")) => {
          let word = switch c.kind {
          | Uncollect({flowKind: List}) => "list"
          | _ => "option"
          }
          Array.push(stages, "-> open " ++ word)
          mark(c)
          chainForward(ValuePort(c, "element"), stages)
        }
      | Uncollect({flowKind: Case({alts, discriminator}), input}) if sameValue(input, cur) => {
          Array.push(
            stages,
            "-> split " ++ termOf(discriminator) ++ " of " ++ alts->Array.join(", "),
          )
          mark(c)
          // terminal: the split yields a handle, named with `=> csN`.
          (cur, Some(nodeName(nm, c)))
        }
      | Collect({branches}) =>
        switch classifyCollect(branches) {
        | IterCollect =>
          switch branches[0] {
          | Some({flow, value}) if sameValue(value, cur) => {
              let op = if implicitFlow(flow) {
                "-~> collect"
              } else {
                "-~> collect ~" ++ flowName(flow)
              }
              Array.push(stages, op)
              mark(c)
              chainForward(ValuePort(c, "value"), stages)
            }
          | _ => (cur, None)
          }
        | _ => (cur, None) // case / partial collect: a lane group, printed on its own
        }
      | _ => (cur, None)
      }
    | _ => (cur, None)
    }

  // Emit one statement rooted at a chain head, then everything it fuses.
  let emitChainHead = (head: node, sources: array<string>, firstStage: string, cur0: valueRef): unit => {
    mark(head)
    let stages = [firstStage]
    let (finalV, splitName) = chainForward(cur0, stages)
    let binder = switch splitName {
    | Some(name) => "=> " ++ name
    | None => "=> " ++ valueName(finalV)
    }
    let srcTxt = sources->Array.join(", ")
    let body = if Array.length(stages) === 0 {
      srcTxt ++ " " ++ binder
    } else {
      srcTxt ++ " " ++ stages->Array.join(" ") ++ " " ++ binder
    }
    Array.push(lines, body)
  }

  // --- statement units and their ordering -------------------------------------
  //
  // Fusing a chain onto its head means the whole chain prints at the head's
  // slot — so a chain that references a name (a fn literal, a named flow, a
  // junction value) must print AFTER the statement that binds it. Node order
  // does not guarantee that (the referenced binder can define a name consumed
  // by a *later* fused node), so units are ordered by a topological sort over
  // their name dependencies. A "unit" is a head node plus the nodes it fuses.

  // The consumer fused after `cur`, matching chainForward's continuation rule.
  let continuationOf = (cur: valueRef): option<node> =>
    switch soleNodeConsumer(cur) {
    | Some(c) =>
      switch c.kind {
      | App({args})
        if Array.length(args) >= 1 &&
        (switch args[0] {
        | Some(a0) => sameValue(a0, cur)
        | None => false
        }) =>
        Some(c)
      | Uncollect({flowKind: List | Option, input, nesting: None})
        if sameValue(input, cur) && implicitFlow(FlowPort(c, "flow")) =>
        Some(c)
      | Uncollect({flowKind: Case(_), input}) if sameValue(input, cur) => Some(c)
      | Collect({branches}) =>
        switch classifyCollect(branches) {
        | IterCollect =>
          switch branches[0] {
          | Some({value}) if sameValue(value, cur) => Some(c)
          | _ => None
          }
        | _ => None
        }
      | _ => None
      }
    | None => None
    }
  // The value a fused node produces to continue the chain (None => terminal).
  let nextCurOf = (c: node): option<valueRef> =>
    switch c.kind {
    | App(_) | Collect(_) => Some(ValuePort(c, "value"))
    | Uncollect({flowKind: List | Option}) => Some(ValuePort(c, "element"))
    | _ => None // a split is terminal (yields a handle)
    }
  // The value a head produces to begin its chain (None => standalone/terminal).
  let headStart = (h: node): option<valueRef> =>
    switch h.kind {
    | App({args}) => Array.length(args) >= 1 ? Some(ValuePort(h, "value")) : None
    | Uncollect({flowKind: List | Option, nesting: None}) =>
      implicitFlow(FlowPort(h, "flow")) ? Some(ValuePort(h, "element")) : None
    | Collect({branches}) =>
      switch classifyCollect(branches) {
      | IterCollect => Some(ValuePort(h, "value"))
      | _ => None
      }
    | _ => None
    }

  // Assign every non-inline node to its unit head. Iterating in `order`
  // (inputs before consumers) means a head is always reached before the
  // members it fuses, so the first unassigned node of a chain is its head.
  let headOf: Map.t<int, int> = Map.make()
  let heads: array<node> = []
  order->Array.forEach(h =>
    if !inlineLit(h) && !Map.has(headOf, h.id) {
      Array.push(heads, h)
      Map.set(headOf, h.id, h.id)
      let rec go = (cur: valueRef) =>
        switch continuationOf(cur) {
        | Some(c) => {
            Map.set(headOf, c.id, h.id)
            switch nextCurOf(c) {
            | Some(nc) => go(nc)
            | None => ()
            }
          }
        | None => ()
        }
      switch headStart(h) {
      | Some(c) => go(c)
      | None => ()
      }
    }
  )

  // Dependency edges between units: hp must precede hm whenever some node in
  // unit hm reads a name bound by a node in unit hp (a cross-unit input, an
  // inline literal excepted — it carries no statement).
  let indeg: Map.t<int, int> = Map.make()
  let adj: Map.t<int, array<int>> = Map.make()
  let seenEdge: Map.t<string, bool> = Map.make()
  heads->Array.forEach(h => Map.set(indeg, h.id, 0))
  let addEdge = (from: int, to_: int) =>
    if from !== to_ {
      let ek = Int.toString(from) ++ ">" ++ Int.toString(to_)
      if !Map.has(seenEdge, ek) {
        Map.set(seenEdge, ek, true)
        let a = switch Map.get(adj, from) {
        | Some(a) => a
        | None => {
            let a: array<int> = []
            Map.set(adj, from, a)
            a
          }
        }
        Array.push(a, to_)
        Map.set(indeg, to_, Map.get(indeg, to_)->Option.getOr(0) + 1)
      }
    }
  let depOn = (consumer: node, producer: node) =>
    if !inlineLit(producer) {
      switch (Map.get(headOf, producer.id), Map.get(headOf, consumer.id)) {
      | (Some(hp), Some(hm)) => addEdge(hp, hm)
      | _ => ()
      }
    }
  p.nodes->Array.forEach(m => {
    let ins = inputs(m)
    ins.values->Array.forEach(v => depOn(m, nodeOfValue(v)))
    ins.flows->Array.forEach(f => depOn(m, nodeOfFlow(f)))
    ins.pairedReads->Array.forEach(r => depOn(m, r))
  })

  // Kahn's algorithm; ties broken by original `order` index for a stable print.
  let idxOf: Map.t<int, int> = Map.make()
  heads->Array.forEachWithIndex((h, i) => Map.set(idxOf, h.id, i))
  let sortedHeads: array<node> = []
  let ready: array<node> = heads->Array.filter(h => Map.get(indeg, h.id)->Option.getOr(0) === 0)
  let ready = ref(ready)
  while Array.length(ready.contents) > 0 {
    // pop the ready head with the smallest order index
    ready := ready.contents->Array.toSorted((a, b) =>
      Float.fromInt(Map.get(idxOf, a.id)->Option.getOr(0) - Map.get(idxOf, b.id)->Option.getOr(0))
    )
    let h = ready.contents->Array.getUnsafe(0)
    ready := ready.contents->Array.slice(~start=1)
    Array.push(sortedHeads, h)
    Map.get(adj, h.id)->Option.getOr([])->Array.forEach(to_ => {
      let d = Map.get(indeg, to_)->Option.getOr(0) - 1
      Map.set(indeg, to_, d)
      if d === 0 {
        switch order->Array.find(n => n.id === to_) {
        | Some(n) => Array.push(ready.contents, n)
        | None => ()
        }
      }
    })
  }
  // Any head left out (would only happen on a cycle, impossible by
  // construction) is appended in order so the print stays total.
  heads->Array.forEach(h =>
    if !Array.some(sortedHeads, s => s.id === h.id) {
      Array.push(sortedHeads, h)
    }
  )

  sortedHeads->Array.forEach(n =>
    if !Map.has(emitted, n.id) {
      switch n.kind {
      | Lit(js) => {
          mark(n)
          Array.push(lines, valueName(ValuePort(n, "value")) ++ " = " ++ litText(js))
        }
      | App({fn, args}) =>
        if Array.length(args) === 0 {
          // Zero-arg application: no topic. Prints as a call (grammar growth
          // path — not yet reparsed, but total).
          mark(n)
          Array.push(lines, termOf(fn) ++ "() => " ++ valueName(ValuePort(n, "value")))
        } else {
          let sources = args->Array.map(termOf)
          emitChainHead(n, sources, "-> " ++ termOf(fn), ValuePort(n, "value"))
        }
      | Uncollect({flowKind: List | Option, input, nesting}) => {
          let word = switch n.kind {
          | Uncollect({flowKind: List}) => "list"
          | _ => "option"
          }
          let nestTxt = switch nesting {
          | Some(f) => " in ~" ++ flowName(f)
          | None => ""
          }
          if nesting === None && implicitFlow(FlowPort(n, "flow")) {
            // implicit flow: fuse the element forward, no `~name`.
            emitChainHead(n, [termOf(input)], "-> open " ++ word, ValuePort(n, "element"))
          } else {
            // named flow: a terminal open binding element + flow.
            mark(n)
            Array.push(
              lines,
              termOf(input) ++
              " -> open " ++
              word ++
              nestTxt ++
              " => " ++
              valueName(ValuePort(n, "element")) ++
              ", ~" ++
              flowName(FlowPort(n, "flow")),
            )
          }
        }
      | Uncollect({flowKind: Case({alts, discriminator}), input, nesting}) => {
          mark(n)
          let nestTxt = switch nesting {
          | Some(f) => " in ~" ++ flowName(f)
          | None => ""
          }
          Array.push(
            lines,
            termOf(input) ++
            " -> split " ++
            termOf(discriminator) ++
            " of " ++
            alts->Array.join(", ") ++
            nestTxt ++
            " => " ++
            nodeName(nm, n),
          )
        }
      | Collect({branches}) =>
        switch classifyCollect(branches) {
        | IterCollect =>
          switch branches[0] {
          | Some({flow, value}) => {
              let op = if implicitFlow(flow) {
                "-~> collect"
              } else {
                "-~> collect ~" ++ flowName(flow)
              }
              emitChainHead(n, [termOf(value)], op, ValuePort(n, "value"))
            }
          | None => mark(n) // malformed; nothing to print
          }
        | CaseFull | CasePartial(_) | Malformed(_) => {
            mark(n)
            // lane group gathered by a postfix collect (case collect, full or
            // partial). Emitted as its own multi-line statement.
            branches->Array.forEach(b =>
              Array.push(lines, "~" ++ flowName(b.flow) ++ ": " ++ termOf(b.value))
            )
            let flowOut = switch classifyCollect(branches) {
            | CasePartial(_) => ", ~" ++ flowName(FlowPort(n, "flow"))
            | _ => ""
            }
            Array.push(
              lines,
              "-~> collect => " ++ valueName(ValuePort(n, "value")) ++ flowOut,
            )
          }
        }
      | Join({outer, inner}) => {
          mark(n)
          Array.push(
            lines,
            "~" ++
            flowName(inner) ++
            " ~> join into ~" ++
            flowName(outer) ++
            " => ~" ++
            flowName(FlowPort(n, "flow")),
          )
        }
      | Commute({outer, inner}) => {
          mark(n)
          Array.push(
            lines,
            "~" ++
            flowName(inner) ++
            " ~> commute out of ~" ++
            flowName(outer) ++
            " => " ++
            nodeName(nm, n),
          )
        }
      | Cross({left, right}) => {
          mark(n)
          // The standalone product form, parsed by TextParse / resolved by
          // TextResolve (round-trips — Main 15/15b). The `cross with`
          // surface spelling itself is still provisional at the design level
          // (product-flows-design.md's textual form is owed); the wiring it
          // denotes is settled.
          Array.push(
            lines,
            "~" ++
            flowName(left) ++
            " ~> cross with ~" ++
            flowName(right) ++
            " => ~" ++
            flowName(FlowPort(n, "flow")),
          )
        }
      | DelayRead({flow, init}) => {
          mark(n)
          Array.push(
            lines,
            "~" ++
            flowName(flow) ++
            " ~> delay init " ++
            termOf(init) ++
            " => " ++
            valueName(ValuePort(n, "prev")),
          )
        }
      | DelayWrite({read, step}) => {
          mark(n)
          Array.push(
            lines,
            termOf(step) ++
            " -> step of " ++
            valueName(ValuePort(read, "prev")) ++
            " => " ++
            valueName(ValuePort(n, "final")),
          )
        }
      }
    }
  )

  p.outputs->Array.forEach(o => {
    let bound = switch o.source {
    | ValuePort(n, port) =>
      if namedAsNode(n) {
        valueName(o.source)
      } else {
        portName(nm, n, port, "n")
      }
    }
    if bound === o.name {
      Array.push(lines, "out " ++ o.name)
    } else {
      Array.push(lines, "out " ++ o.name ++ " = " ++ bound)
    }
  })

  lines->Array.join("\n") ++ "\n"
}
